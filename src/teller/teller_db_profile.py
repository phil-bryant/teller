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

import json
import os
import ctypes
import shlex
from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path
from typing import Optional
import structlog


_ALLOWED_SSLMODES = {"disable", "allow", "prefer", "require", "verify-ca", "verify-full"}
_ALLOWED_TARGETS = {"local", "managed", "sqlite"}
log = structlog.get_logger()


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
    sqlite_path: str
    sqlcipher_key: str


class ProfileError(RuntimeError):
    """Raised when profile lookup or validation fails."""


#R010: Read required profile connection fields from libonepsa.
def _read_onepsa_fields(item: str, fields: tuple[str, ...]) -> dict[str, str]:
    """Read multiple fields from a 1psa item in a single CLI call. Returns field→value map."""
    parsed: dict[str, str] = {}
    lib_path = os.environ.get("ONEPSA_LIB_PATH", "/usr/local/lib/libonepsa.dylib")
    try:
        lib = ctypes.CDLL(lib_path)
    except OSError:
        return {}
    lib.OnepsaStringFree.argtypes = [ctypes.c_void_p]
    lib.OnepsaStringFree.restype = None
    lib.OnepsaGetField.argtypes = [
        ctypes.c_char_p,
        ctypes.c_char_p,
        ctypes.POINTER(ctypes.c_char_p),
    ]
    lib.OnepsaGetField.restype = ctypes.c_void_p

    for field in fields:
        err = ctypes.c_char_p()
        out_ptr = lib.OnepsaGetField(item.encode("utf-8"), field.encode("utf-8"), ctypes.byref(err))
        if err.value is not None:
            message = err.value.decode("utf-8")
            onepsa_cmd = f"1psa -f {shlex.quote(item)} {shlex.quote(field)}"
            env_key = f"{item}.{field}"
            log.warning(
                "1Password field lookup failed; falling back to ~/.env",
                item=item,
                field=field,
                onepsa_command=onepsa_cmd,
                env_fallback_key=env_key,
                error=message,
            )
            lib.OnepsaStringFree(err)
            # Stop after the first libonepsa error so callers can immediately
            # fall back to ~/.env without repeating the same failing request
            # for every field.
            break
        if not out_ptr:
            continue
        out = ctypes.cast(out_ptr, ctypes.c_char_p).value
        lib.OnepsaStringFree(out_ptr)
        value = (out or b"").decode("utf-8").strip()
        if value:
            parsed[field] = value
    return parsed


#R010: Read a single profile field from libonepsa.
def _read_onepsa_field(item: str, field: str) -> Optional[str]:
    """Read a single field from a 1psa item. Returns None on missing field."""
    fields = _read_onepsa_fields(item, (field,))
    return fields.get(field) or None


_CONNECTION_FIELDS = (
    "host",
    "port",
    "database",
    "username",
    "schema",
    "runtime_role",
    "target",
    "sslmode",
    "sqlcipher_key",
)


#R010: Parse ~/.env fallback values for profile connection fields.
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
    fields = _read_onepsa_fields(item, _CONNECTION_FIELDS)
    if not fields.get("host"):
        env_fields = _read_env_file_fields(item)
        if env_fields:
            return _record_from_fields(env_fields)
    return _record_from_fields(fields)


#R010: Normalize raw field maps into validated connection records.
def _record_from_fields(fields: dict[str, str]) -> dict:
    """Build a record dict from a flat field→value mapping (either 1psa or ~/.env)."""
    return _build_record(
        host=fields.get("host"),
        port_raw=fields.get("port"),
        database=fields.get("database"),
        username=fields.get("username"),
        password_raw=fields.get("password"),
        schema=fields.get("schema"),
        runtime_role=fields.get("runtime_role"),
        target=fields.get("target"),
        sslmode=fields.get("sslmode"),
        sqlite_path_raw=fields.get("sqlite_path"),
        sqlcipher_key_raw=fields.get("sqlcipher_key"),
    )


#R010: Parse profile port values with safe default fallback.
def _parse_port(port_raw: str | None) -> int:
    try:
        return int(port_raw) if port_raw else 5432
    except (TypeError, ValueError):
        return 5432


#R010: Resolve the profile target to an allowed runtime backend.
def _resolve_target(target: str | None) -> str:
    return target if target in _ALLOWED_TARGETS else "local"


#R010: Validate and normalize sslmode for the resolved backend target.
def _resolve_sslmode(sslmode: str | None, resolved_target: str) -> str:
    if resolved_target == "sqlite":
        return "disable"
    candidate = (sslmode or "").strip()
    if not candidate:
        return "require" if resolved_target == "managed" else "disable"
    if candidate in _ALLOWED_SSLMODES:
        return candidate
    allowed = ", ".join(sorted(_ALLOWED_SSLMODES))
    raise ProfileError(f"DB profile sslmode must be one of {allowed}; got {candidate!r}")


#R010: Build canonical profile records for postgres/supabase/sqlite targets.
def _build_record(
    host,
    port_raw,
    database,
    username,
    password_raw,
    schema,
    runtime_role,
    target,
    sslmode,
    sqlite_path_raw=None,
    sqlcipher_key_raw=None,
) -> dict:
    resolved_target = _resolve_target(target)
    sqlite_path = ""
    sqlcipher_key = ""
    if resolved_target == "sqlite":
        sqlite_path = (sqlite_path_raw or database or "").strip()
        if not sqlite_path:
            sqlite_path = str(Path.cwd() / ".database" / "teller.sqlite3")
        # LOCALHOST_SQLITE_* fallbacks traditionally store the SQLCipher key as
        # ".password". Prefer explicit sqlcipher_key, then reuse password.
        sqlcipher_key = (sqlcipher_key_raw or password_raw or "").strip()
    return {
        "host": "" if resolved_target == "sqlite" else (host or "localhost"),
        "port": 0 if resolved_target == "sqlite" else _parse_port(port_raw),
        "dbname": "" if resolved_target == "sqlite" else (database or "prod"),
        "user": "" if resolved_target == "sqlite" else (username or "teller"),
        "search_path": "teller" if resolved_target == "sqlite" else (schema or "teller,classy,matchy"),
        "runtime_role": "" if resolved_target == "sqlite" else (runtime_role or ""),
        "target": resolved_target,
        "sslmode": _resolve_sslmode(sslmode, resolved_target),
        "sqlite_path": sqlite_path,
        "sqlcipher_key": sqlcipher_key,
    }


#R021: Coerce resolved records to sqlite semantics when sqlite profile is selected.
def _force_sqlite_target(record: dict) -> dict:
    """Normalize a resolved record to sqlite target semantics."""
    sqlite_path = (record.get("sqlite_path") or "").strip()
    if not sqlite_path:
        sqlite_path = str(Path.cwd() / ".database" / "teller.sqlite3")
    sqlcipher_key = (record.get("sqlcipher_key") or "").strip()
    return {
        "host": "",
        "port": 0,
        "dbname": "",
        "user": "",
        "search_path": "teller",
        "runtime_role": "",
        "target": "sqlite",
        "sslmode": "disable",
        "sqlite_path": sqlite_path,
        "sqlcipher_key": sqlcipher_key,
    }


#R005: Profile-file search order. ``~/.teller/db_profiles.json`` is the canonical
#R005: shared location; ``./config`` hosts repo-local profile files.
def _candidate_profile_paths() -> list[Path]:
    explicit = os.environ.get("TELLER_DB_PROFILE_FILE", "").strip()
    paths: list[Path] = []
    if explicit:
        paths.append(Path(explicit).expanduser())
    paths.append(Path.home() / ".teller" / "db_profiles.json")
    paths.append(Path.cwd() / "config" / "db-profiles.local.json")
    paths.append(Path.cwd() / "config" / "db-profiles.json")
    return paths


#R001: Fingerprint profile files so cache invalidates when files change.
def _profile_file_fingerprint(path: Path) -> tuple[str, int, int]:
    try:
        stat = path.stat()
    except OSError:
        return (str(path), -1, -1)
    return (str(path), stat.st_mtime_ns, stat.st_size)


#R001: Build the cache key from env overrides and profile-file fingerprints.
def _profile_cache_key() -> tuple:
    env_values = tuple(
        os.environ.get(name, "")
        for name in (
            "TELLER_DB_PROFILE",
            "TELLER_DB_PROFILE_FILE",
            "TELLER_DB_HOST",
            "TELLER_DB_PORT",
            "TELLER_DB_NAME",
            "TELLER_DB_USER",
            "TELLER_DB_ROLE",
            "TELLER_DB_SSLMODE",
            "TELLER_DB_SEARCH_PATH",
            "TELLER_DB_SQLITE_PATH",
            "TELLER_DB_SQLCIPHER_KEY",
            "ONEPSA_LIB_PATH",
        )
    )
    fingerprints = tuple(_profile_file_fingerprint(path) for path in _candidate_profile_paths())
    return (str(Path.cwd()), env_values, fingerprints)


#R010: Load the first existing profile file, or fail with setup guidance.
def _load_profile_document() -> dict:
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
    raise ProfileError(
        "No DB profile file found. Create one with: cp config/db-profiles-EXAMPLE.json config/db-profiles.json"
    )


#R015: Choose the active profile name. ``TELLER_DB_PROFILE`` beats the file's
#R015: ``default_profile`` field.
def _select_profile_name(document: dict) -> str:
    override = os.environ.get("TELLER_DB_PROFILE", "").strip()
    if override:
        return override
    if isinstance(document.get("default_profile"), str) and document["default_profile"].strip():
        return document["default_profile"].strip()
    raise ProfileError(
        "DB profile file is missing a non-empty 'default_profile'. "
        "Copy config/db-profiles-EXAMPLE.json and choose a default profile."
    )


#R010: Resolve and validate the onepsa item pointer for the selected profile.
def _resolve_onepsa_item(document: dict, name: str) -> str:
    """Get the 1psa item name for a given profile."""
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
    if value := os.environ.get("TELLER_DB_SQLITE_PATH"):
        overridden["sqlite_path"] = value
        overridden["target"] = "sqlite"
        overridden["host"] = ""
        overridden["port"] = 0
        overridden["dbname"] = ""
        overridden["user"] = ""
        overridden["runtime_role"] = ""
        overridden["sslmode"] = "disable"
    if (value := os.environ.get("TELLER_DB_SQLCIPHER_KEY")) is not None:
        overridden["sqlcipher_key"] = value.strip()
    return overridden


#R001: Public entry point used by ``teller_db.get_engine``.
@lru_cache(maxsize=32)
def _resolve_profile_cached(_cache_key: tuple) -> ResolvedProfile:
    document = _load_profile_document()
    name = _select_profile_name(document)
    onepsa_item = _resolve_onepsa_item(document, name)
    record = _fetch_record_from_onepsa(onepsa_item)
    final = _apply_env_overrides(record)
    #R021: sqlite profile name must resolve sqlite target even when 1psa target
    # metadata is missing/stale (common fallback path when ~/.env supplies values).
    if name == "sqlite":
        #R021: The SQLCipher file path is per-machine configuration, so an explicit
        #R021: ~/.env sqlite_path beats 1psa-derived values (which often only carry
        #R021: a postgres-style database name) and prevents the cwd-relative
        #R021: default from splitting data across repos. The TELLER_DB_SQLITE_PATH
        #R021: env var, applied above, still wins outright.
        if not os.environ.get("TELLER_DB_SQLITE_PATH", "").strip():
            env_fields = _read_env_file_fields(onepsa_item)
            if (env_fields.get("sqlite_path") or "").strip():
                final["sqlite_path"] = env_fields["sqlite_path"].strip()
        final = _force_sqlite_target(final)
        if not (final.get("sqlcipher_key") or "").strip():
            env_fields = _read_env_file_fields(onepsa_item)
            final["sqlcipher_key"] = (
                (env_fields.get("sqlcipher_key") or "").strip()
                or (env_fields.get("password") or "").strip()
            )
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
        sqlite_path=final["sqlite_path"],
        sqlcipher_key=final["sqlcipher_key"],
    )


def resolve_profile() -> ResolvedProfile:
    #R001: Cache profile resolution by effective env + profile file fingerprint.
    #R001: This keeps reads deterministic across reruns while still refreshing on env/file changes.
    return _resolve_profile_cached(_profile_cache_key())


#R001: Expose cache reset hook for tests that mutate profile inputs.
def reset_profile_cache() -> None:
    """Clear the cached profile so tests can mutate env/files between assertions."""
    _resolve_profile_cached.cache_clear()
