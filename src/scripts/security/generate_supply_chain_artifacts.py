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
from typing import Iterable

REQ_LINE_RE = re.compile(r"^([A-Za-z0-9_.-]+)==([A-Za-z0-9_.!+-]+)$")


def sha256_file(path: pathlib.Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as fh:
        while True:
            chunk = fh.read(65536)
            if not chunk:
                break
            digest.update(chunk)
    return digest.hexdigest()


def parse_pinned_requirements(path: pathlib.Path) -> list[dict[str, str]]:
    components: list[dict[str, str]] = []
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("--hash="):
            continue
        if line.startswith("--"):
            continue
        if " \\" in line:
            line = line.split(" \\")[0].strip()
        match = REQ_LINE_RE.match(line)
        if not match:
            continue
        name, version = match.groups()
        components.append({"name": name, "version": version})
    return components


def build_cyclonedx(
    runtime_components: list[dict[str, str]],
    security_components: list[dict[str, str]],
) -> dict:
    timestamp = dt.datetime.now(dt.timezone.utc).isoformat()
    components = []
    for pkg in runtime_components:
        components.append(
            {
                "type": "library",
                "name": pkg["name"],
                "version": pkg["version"],
                "scope": "required",
            }
        )
    for pkg in security_components:
        components.append(
            {
                "type": "library",
                "name": pkg["name"],
                "version": pkg["version"],
                "scope": "optional",
            }
        )

    return {
        "bomFormat": "CycloneDX",
        "specVersion": "1.5",
        "version": 1,
        "metadata": {
            "timestamp": timestamp,
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


def sign_sbom_with_cosign(sbom_path: pathlib.Path, signature_path: pathlib.Path) -> bool:
    if not has_command("cosign"):
        return False
    cosign_key = os.getenv("COSIGN_KEY", "").strip()
    if not cosign_key:
        return False
    result = subprocess.run(
        [
            "cosign",
            "sign-blob",
            "--yes",
            "--key",
            cosign_key,
            "--output-signature",
            str(signature_path),
            str(sbom_path),
        ],
        check=False,
        capture_output=True,
        text=True,
    )
    return result.returncode == 0 and signature_path.exists()


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
        if sign_sbom_with_cosign(sbom_path, signature_path):
            signature_mode = "cosign"
        else:
            if args.signing_mode == "required":
                raise SystemExit(
                    "Signing mode is required, but cosign signing context is unavailable."
                )
            write_scaffold_signature(
                signature_path,
                sbom_sha,
                "cosign unavailable or COSIGN_KEY not configured",
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
