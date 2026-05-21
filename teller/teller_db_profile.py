"""Database profile resolution for Teller.

Profiles let the same code talk to either a local PostgreSQL or a Supabase-hosted
PostgreSQL without changing source. The JSON config is just a pointer to a 1psa
item; all connection metadata lives in 1psa. Explicit ``TELLER_DB_*`` environment
variables still win so existing shell scripts and bats tests keep working unchanged.

#R001: Define the resolved profile data shape.
#R005: Locate the active profile file via search order.
#R010: Load and validate JSON profile records.
#R015: Resolve the active profile name with env override.
#R020: Apply environment variable overrides on top of the profile.
"""

from __future__ import annotations

import ctypes
import json
import os
from dataclasses import dataclass
from pathlib import Path
from typing import Optional


_ALLOWED_SSLMODES = {"disable", "allow", "prefer", "require", "verify-ca", "verify-full"}
_ALLOWED_TARGETS = {"local", "managed"}


#R001: Resolved record shape consumed by ``teller_db.get_engine``.
@dataclass(frozen=True)
class ResolvedProfile:
    name: str
    host: str
    port: int
    dbname: str
    user: str
    onepsa_item: str
    search_path: str
    runtime_role: str
    sslmode: str
    target: str


class ProfileError(RuntimeError):
    """Raised when profile lookup or validation fails."""


def _read_onepsa_field(item: str, field: str) -> Optional[str]:
    """Read a single field from a 1psa item via libonepsa. Returns None on missing field."""
    lib_path = os.environ.get("ONEPSA_LIB_PATH", "/usr/local/lib/libonepsa.dylib")
    try:
        lib = ctypes.CDLL(lib_path)
    except OSError:
        return None
    lib.OnepsaStringFree.argtypes = [ctypes.c_void_p]
    lib.OnepsaStringFree.restype = None
    lib.OnepsaGetField.argtypes = [
        ctypes.c_char_p,
        ctypes.c_char_p,
        ctypes.POINTER(ctypes.c_char_p),
    ]
    lib.OnepsaGetField.restype = ctypes.c_void_p
    err = ctypes.c_char_p()
    out_ptr = lib.OnepsaGetField(item.encode("utf-8"), field.encode("utf-8"), ctypes.byref(err))
    if err.value is not None:
        message = err.value.decode("utf-8")
        lib.OnepsaStringFree(err)
        return None
    if not out_ptr:
        return None
    out = ctypes.cast(out_ptr, ctypes.c_char_p).value
    lib.OnepsaStringFree(out_ptr)
    return (out or b"").decode("utf-8").strip() or None


def _read_env_file_fields(item: str) -> dict[str, str]:
    """Parse ~/.env for lines matching ITEM.field=value and return a field→value dict."""
    env_path = Path.home() / ".env"
    if not env_path.is_file():
        return {}
    prefix = item + "."
    fields: dict[str, str] = {}
    try:
        for raw_line in env_path.read_text(encoding="utf-8").splitlines():
            line = raw_line.strip()
            if not line or line.startswith("#"):
                continue
            if not line.startswith(prefix):
                continue
            rest = line[len(prefix):]
            if "=" not in rest:
                continue
            field_name, _, value = rest.partition("=")
            field_name = field_name.strip()
            value = value.strip()
            if field_name:
                fields[field_name] = value
    except OSError:
        pass
    return fields


#R010: Fetch all connection fields from 1psa first; fall back to ~/.env if 1psa is unavailable.
def _fetch_record_from_onepsa(item: str) -> dict:
    host = _read_onepsa_field(item, "host")
    # If 1psa returned nothing for host, try ~/.env as fallback source for all fields.
    if host is None:
        env_fields = _read_env_file_fields(item)
        if env_fields:
            return _record_from_fields(env_fields)
    port_raw = _read_onepsa_field(item, "port")
    database = _read_onepsa_field(item, "database")
    username = _read_onepsa_field(item, "username")
    schema = _read_onepsa_field(item, "schema")
    runtime_role = _read_onepsa_field(item, "runtime_role")
    target = _read_onepsa_field(item, "target")
    sslmode = _read_onepsa_field(item, "sslmode")
    return _build_record(host, port_raw, database, username, schema, runtime_role, target, sslmode)


def _record_from_fields(fields: dict[str, str]) -> dict:
    """Build a record dict from a flat field→value mapping (either 1psa or ~/.env)."""
    return _build_record(
        host=fields.get("host"),
        port_raw=fields.get("port"),
        database=fields.get("database"),
        username=fields.get("username"),
        schema=fields.get("schema"),
        runtime_role=fields.get("runtime_role"),
        target=fields.get("target"),
        sslmode=fields.get("sslmode"),
    )


def _build_record(host, port_raw, database, username, schema, runtime_role, target, sslmode) -> dict:
    try:
        port = int(port_raw) if port_raw else 5432
    except (TypeError, ValueError):
        port = 5432
    resolved_target = target if target in _ALLOWED_TARGETS else "local"
    if not sslmode:
        sslmode = "require" if resolved_target == "managed" else "disable"
    return {
        "host": host or "localhost",
        "port": port,
        "dbname": database or "prod",
        "user": username or "teller",
        "search_path": schema or "teller",
        "runtime_role": runtime_role or "",
        "target": resolved_target,
        "sslmode": sslmode if sslmode in _ALLOWED_SSLMODES else "disable",
    }


#R005: Profile-file search order. ``~/.teller/db_profiles.json`` is the canonical
#R005: shared location; ``./db-profiles.json`` lets a checkout override locally
#R005: (and ``./db-profiles.local.json`` is gitignored for per-developer secrets).
def _candidate_profile_paths() -> list[Path]:
    explicit = os.environ.get("TELLER_DB_PROFILE_FILE", "").strip()
    paths: list[Path] = []
    if explicit:
        paths.append(Path(explicit).expanduser())
    paths.append(Path.home() / ".teller" / "db_profiles.json")
    paths.append(Path.cwd() / "db-profiles.local.json")
    paths.append(Path.cwd() / "db-profiles.json")
    return paths


#R010: Load the first existing profile file, or ``None`` if none exist.
def _load_profile_document() -> Optional[dict]:
    for path in _candidate_profile_paths():
        if not path.is_file():
            continue
        try:
            payload = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, ValueError) as exc:
            raise ProfileError(f"Could not read DB profile file {path}: {exc}") from exc
        if not isinstance(payload, dict):
            raise ProfileError(f"DB profile file {path} must contain a JSON object")
        profiles = payload.get("profiles")
        if not isinstance(profiles, dict) or not profiles:
            raise ProfileError(f"DB profile file {path} is missing a non-empty 'profiles' object")
        return payload
    return None


#R015: Choose the active profile name. ``TELLER_DB_PROFILE`` beats the file's
#R015: ``default_profile`` field; ``"local"`` is the final fallback so a fresh
#R015: checkout boots without any config.
def _select_profile_name(document: Optional[dict]) -> str:
    override = os.environ.get("TELLER_DB_PROFILE", "").strip()
    if override:
        return override
    if document and isinstance(document.get("default_profile"), str) and document["default_profile"].strip():
        return document["default_profile"].strip()
    return "local"


def _resolve_onepsa_item(document: Optional[dict], name: str) -> str:
    """Get the 1psa item name for a given profile."""
    if document is None:
        return "localhost_postgres_teller"
    profiles = document.get("profiles") or {}
    record = profiles.get(name)
    if not isinstance(record, dict):
        available = ", ".join(sorted(profiles.keys())) or "<none>"
        raise ProfileError(f"DB profile {name!r} not found; available profiles: {available}")
    item = record.get("1psa_or_env_item", "").strip()
    if not item:
        item = record.get("1psa_item", "").strip()
    if not item:
        raise ProfileError(f"DB profile {name!r} is missing '1psa_or_env_item'")
    return item


#R020: Apply env overrides on top of the profile so existing scripts and bats
#R020: tests that set ``TELLER_DB_HOST``/``PORT``/``NAME``/``USER``/``ROLE`` keep
#R020: their behavior. ``TELLER_PSA_ITEM`` overrides ``onepsa_item``.
def _apply_env_overrides(record: dict) -> dict:
    overridden = dict(record)
    if value := os.environ.get("TELLER_DB_HOST"):
        overridden["host"] = value
    if value := os.environ.get("TELLER_DB_PORT"):
        try:
            overridden["port"] = int(value)
        except ValueError as exc:
            raise ProfileError(f"TELLER_DB_PORT must be an integer; got {value!r}") from exc
    if value := os.environ.get("TELLER_DB_NAME"):
        overridden["dbname"] = value
    if value := os.environ.get("TELLER_DB_USER"):
        overridden["user"] = value
    if (value := os.environ.get("TELLER_DB_ROLE")) is not None:
        overridden["runtime_role"] = value.strip()
    if value := os.environ.get("TELLER_DB_SSLMODE"):
        candidate = value.strip()
        if candidate not in _ALLOWED_SSLMODES:
            allowed = ", ".join(sorted(_ALLOWED_SSLMODES))
            raise ProfileError(f"TELLER_DB_SSLMODE must be one of {allowed}; got {candidate!r}")
        overridden["sslmode"] = candidate
    if value := os.environ.get("TELLER_DB_SEARCH_PATH"):
        overridden["search_path"] = value
    return overridden


#R001: Public entry point used by ``teller_db.get_engine``.
def resolve_profile() -> ResolvedProfile:
    document = _load_profile_document()
    name = _select_profile_name(document)
    onepsa_item = _resolve_onepsa_item(document, name)
    record = _fetch_record_from_onepsa(onepsa_item)
    final = _apply_env_overrides(record)
    return ResolvedProfile(
        name=name,
        host=final["host"],
        port=final["port"],
        dbname=final["dbname"],
        user=final["user"],
        onepsa_item=onepsa_item,
        search_path=final["search_path"],
        runtime_role=final["runtime_role"],
        sslmode=final["sslmode"],
        target=final["target"],
    )
