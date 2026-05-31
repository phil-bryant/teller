#!/usr/bin/env python3
"""Generate CycloneDX SBOM and signing scaffold artifacts.

This script is dependency-light by design so it can run in local/CI lanes
without requiring an additional SBOM tool installation.
"""

#R110: Generate SBOM + signing scaffold artifacts for supply-chain verification.

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import os
import pathlib
import re
import subprocess
import sys
import shlex
import uuid
from typing import Iterable

REQ_LINE_RE = re.compile(r"^([A-Za-z0-9_.-]+)==([A-Za-z0-9_.!+-]+)$")
HASH_LINE_RE = re.compile(r"^--hash=sha256:([a-fA-F0-9]{64})$")


def sha256_file(path: pathlib.Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as fh:
        while True:
            chunk = fh.read(65536)
            if not chunk:
                break
            digest.update(chunk)
    return digest.hexdigest()


def normalize_pypi_name(name: str) -> str:
    return re.sub(r"[-_.]+", "-", name).lower()


def build_purl(name: str, version: str) -> str:
    return f"pkg:pypi/{normalize_pypi_name(name)}@{version}"


def parse_pinned_requirements(path: pathlib.Path) -> list[dict[str, object]]:
    components: list[dict[str, object]] = []
    current: dict[str, object] | None = None
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        hash_match = HASH_LINE_RE.match(line)
        if hash_match:
            if current is not None:
                component_hashes = current.setdefault("hashes", [])
                assert isinstance(component_hashes, list)
                component_hashes.append(hash_match.group(1).lower())
            continue
        if line.startswith("--"):
            continue
        if " \\" in line:
            line = line.split(" \\")[0].strip()
        match = REQ_LINE_RE.match(line)
        if not match:
            continue
        name, version = match.groups()
        if current is not None:
            components.append(current)
        current = {"name": name, "version": version, "hashes": []}
    if current is not None:
        components.append(current)
    return components


def merge_components(
    runtime_components: list[dict[str, object]],
    security_components: list[dict[str, object]],
) -> list[dict[str, object]]:
    merged: dict[tuple[str, str], dict[str, object]] = {}
    for scope, component_list in (("required", runtime_components), ("optional", security_components)):
        for component in component_list:
            name = str(component["name"])
            version = str(component["version"])
            key = (normalize_pypi_name(name), version)
            hashes = sorted({str(item).lower() for item in component.get("hashes", [])})
            if key not in merged:
                merged[key] = {
                    "name": name,
                    "version": version,
                    "scope": scope,
                    "hashes": hashes,
                }
                continue
            existing = merged[key]
            if existing["scope"] != "required" and scope == "required":
                existing["scope"] = "required"
            existing_hashes = set(str(item) for item in existing.get("hashes", []))
            existing_hashes.update(hashes)
            existing["hashes"] = sorted(existing_hashes)
    return sorted(
        merged.values(),
        key=lambda entry: (normalize_pypi_name(str(entry["name"])), str(entry["version"])),
    )


def _license_id_from_classifiers(classifiers: list[str]) -> str | None:
    classifier_to_spdx = {
        "License :: OSI Approved :: Apache Software License": "Apache-2.0",
        "License :: OSI Approved :: BSD License": "BSD-3-Clause",
        "License :: OSI Approved :: MIT License": "MIT",
        "License :: OSI Approved :: ISC License (ISCL)": "ISC",
        "License :: OSI Approved :: GNU General Public License v3 (GPLv3)": "GPL-3.0-only",
        "License :: OSI Approved :: GNU Lesser General Public License v3 (LGPLv3)": "LGPL-3.0-only",
        "License :: OSI Approved :: Mozilla Public License 2.0 (MPL 2.0)": "MPL-2.0",
    }
    for classifier in classifiers:
        mapped = classifier_to_spdx.get(classifier.strip())
        if mapped:
            return mapped
    return None


#R115: Fetch license metadata from the canonical PyPI JSON endpoint for each component.
def _percent_encode_path_segment(value: str) -> str:
    safe = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
    encoded_parts: list[str] = []
    for byte in value.encode("utf-8"):
        if byte in safe:
            encoded_parts.append(chr(byte))
        else:
            encoded_parts.append(f"%{byte:02X}")
    return "".join(encoded_parts)


#R115: Resolve CycloneDX licenses[] metadata with deterministic UNKNOWN fallback.
def fetch_component_licenses(name: str, version: str, timeout: float = 5.0) -> list[dict[str, object]]:
    package = _percent_encode_path_segment(name)
    release = _percent_encode_path_segment(version)
    url = f"https://pypi.org/pypi/{package}/{release}/json"
    try:
        response = subprocess.run(
            ["curl", "-fsSL", "--max-time", str(int(timeout)), url],
            check=False,
            capture_output=True,
            text=True,
        )
        if response.returncode != 0:
            return [{"license": {"name": "UNKNOWN"}}]
        payload = json.loads(response.stdout)
    except (OSError, TimeoutError, json.JSONDecodeError):
        return [{"license": {"name": "UNKNOWN"}}]

    info = payload.get("info", {})
    license_expression = str(info.get("license_expression") or "").strip()
    if license_expression:
        return [{"expression": license_expression}]

    license_name = str(info.get("license") or "").strip()
    if license_name and license_name.upper() not in {"UNKNOWN", "N/A"}:
        return [{"license": {"name": license_name}}]

    classifier_id = _license_id_from_classifiers(
        [str(item) for item in info.get("classifiers", []) if isinstance(item, str)]
    )
    if classifier_id:
        return [{"license": {"id": classifier_id}}]
    return [{"license": {"name": "UNKNOWN"}}]


def build_cyclonedx(
    runtime_components: list[dict[str, object]],
    security_components: list[dict[str, object]],
) -> dict:
    timestamp = dt.datetime.now(dt.timezone.utc).isoformat()
    serial_number = f"urn:uuid:{uuid.uuid4()}"
    components = []
    for pkg in merge_components(runtime_components, security_components):
        name = str(pkg["name"])
        version = str(pkg["version"])
        purl = build_purl(name, version)
        hashes = [
            {"alg": "SHA-256", "content": digest}
            for digest in pkg.get("hashes", [])
            if isinstance(digest, str) and digest
        ]
        components.append(
            {
                "type": "library",
                "bom-ref": purl,
                "name": name,
                "version": version,
                "scope": str(pkg.get("scope", "optional")),
                "purl": purl,
                "hashes": hashes,
                "licenses": fetch_component_licenses(name, version),
            }
        )

    return {
        "bomFormat": "CycloneDX",
        "specVersion": "1.5",
        "version": 1,
        "serialNumber": serial_number,
        "metadata": {
            "timestamp": timestamp,
            "component": {
                "type": "application",
                "name": "teller",
                "bom-ref": "pkg:generic/teller@0",
                "purl": "pkg:generic/teller@0",
            },
            "tools": [
                {
                    "vendor": "teller",
                    "name": "generate_supply_chain_artifacts.py",
                    "version": "1",
                }
            ],
        },
        "components": components,
    }


def write_json(path: pathlib.Path, payload: dict) -> None:
    path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")


def has_command(command: str) -> bool:
    return subprocess.run(
        ["bash", "-lc", f"command -v {command} >/dev/null 2>&1"],
        check=False,
    ).returncode == 0


def _run_cosign_sign_blob(
    command: list[str],
    sbom_path: pathlib.Path,
    signature_path: pathlib.Path,
) -> bool:
    result = subprocess.run(
        [*command, "--output-signature", str(signature_path), str(sbom_path)],
        check=False,
        capture_output=True,
        text=True,
    )
    return result.returncode == 0 and signature_path.exists()


def sign_sbom_with_cosign(
    sbom_path: pathlib.Path, signature_path: pathlib.Path
) -> tuple[bool, str]:
    if not has_command("cosign"):
        return False, "cosign command unavailable"
    cosign_key = os.getenv("COSIGN_KEY", "").strip()
    if cosign_key:
        signed = _run_cosign_sign_blob(
            ["cosign", "sign-blob", "--yes", "--key", cosign_key],
            sbom_path,
            signature_path,
        )
        return signed, "cosign key signing failed" if not signed else ""

    if os.getenv("GITHUB_ACTIONS", "").lower() in {"true", "1"}:
        oidc_token = os.getenv("ACTIONS_ID_TOKEN_REQUEST_TOKEN", "").strip()
        if not oidc_token:
            return False, "cosign keyless signing unavailable (missing GitHub OIDC token)"
        #R120: Prefer keyless OIDC signing in GitHub Actions when COSIGN_KEY is unset.
        identity = os.getenv("COSIGN_CERT_IDENTITY", "").strip()
        issuer = os.getenv("COSIGN_CERT_OIDC_ISSUER", "").strip()
        keyless_command = ["cosign", "sign-blob", "--yes"]
        if identity:
            keyless_command.extend(["--certificate-identity", identity])
        if issuer:
            keyless_command.extend(["--certificate-oidc-issuer", issuer])
        signed = _run_cosign_sign_blob(keyless_command, sbom_path, signature_path)
        if not signed:
            return (
                False,
                f"cosign keyless signing failed ({shlex.join(keyless_command)})",
            )
        return True, ""

    return False, "cosign unavailable or COSIGN_KEY not configured"


def write_scaffold_signature(
    signature_path: pathlib.Path, sbom_sha256: str, reason: str
) -> None:
    signature_path.write_text(
        "\n".join(
            [
                "mode=scaffold",
                f"sbom_sha256={sbom_sha256}",
                f"reason={reason}",
                "",
            ]
        ),
        encoding="utf-8",
    )


def main(argv: Iterable[str]) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--runtime-lock", required=True)
    parser.add_argument("--security-lock", required=True)
    parser.add_argument("--output-dir", required=True)
    parser.add_argument(
        "--signing-mode",
        default="scaffold",
        choices=["scaffold", "required", "off"],
        help="scaffold=allow placeholder signature, required=fail if unsigned, off=skip signature creation",
    )
    args = parser.parse_args(list(argv))

    runtime_lock = pathlib.Path(args.runtime_lock)
    security_lock = pathlib.Path(args.security_lock)
    output_dir = pathlib.Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    for lock_path in (runtime_lock, security_lock):
        if not lock_path.exists():
            raise SystemExit(f"Missing lockfile: {lock_path}")

    runtime_components = parse_pinned_requirements(runtime_lock)
    security_components = parse_pinned_requirements(security_lock)
    if not runtime_components and not security_components:
        raise SystemExit("No pinned components discovered from lockfiles.")

    sbom_path = output_dir / "sbom.cdx.json"
    signature_path = output_dir / "sbom.signature"
    attestation_path = output_dir / "sbom.attestation.json"

    sbom_payload = build_cyclonedx(runtime_components, security_components)
    write_json(sbom_path, sbom_payload)

    sbom_sha = sha256_file(sbom_path)
    runtime_sha = sha256_file(runtime_lock)
    security_sha = sha256_file(security_lock)

    signature_mode = "off"
    if args.signing_mode != "off":
        signed, sign_failure_reason = sign_sbom_with_cosign(sbom_path, signature_path)
        if signed:
            signature_mode = "cosign"
        else:
            if args.signing_mode == "required":
                raise SystemExit(
                    f"Signing mode is required, but cosign signing context is unavailable: {sign_failure_reason}"
                )
            write_scaffold_signature(
                signature_path,
                sbom_sha,
                sign_failure_reason,
            )
            signature_mode = "scaffold"

    attestation_payload = {
        "_type": "https://in-toto.io/Statement/v1",
        "subject": [{"name": sbom_path.name, "digest": {"sha256": sbom_sha}}],
        "predicateType": "https://teller.dev/supply-chain/v1",
        "predicate": {
            "runtime_lock_sha256": runtime_sha,
            "security_lock_sha256": security_sha,
            "signature_mode": signature_mode,
            "generated_at": dt.datetime.now(dt.timezone.utc).isoformat(),
        },
    }
    write_json(attestation_path, attestation_payload)
    print(
        json.dumps(
            {
                "sbom": str(sbom_path),
                "signature": str(signature_path) if signature_path.exists() else None,
                "attestation": str(attestation_path),
                "signature_mode": signature_mode,
            }
        )
    )
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
