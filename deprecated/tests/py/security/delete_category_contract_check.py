#!/usr/bin/env python3
import json
import os
import ssl
import sys
import urllib.error
import urllib.request
from urllib.parse import urlparse
import uuid


def request_json(method: str, url: str, write_token: str, body=None):
    data = None if body is None else json.dumps(body).encode("utf-8")
    headers = {"Content-Type": "application/json", "X-Teller-Write-Token": write_token}
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    context = _tls_context_for_url(url)
    try:
        with urllib.request.urlopen(req, timeout=20, context=context) as resp:
            raw = resp.read().decode("utf-8")
            payload = None
            if raw:
                try:
                    payload = json.loads(raw)
                except json.JSONDecodeError:
                    payload = {"raw": raw}
            return resp.status, payload
    except urllib.error.HTTPError as exc:
        raw = exc.read().decode("utf-8")
        payload = None
        if raw:
            try:
                payload = json.loads(raw)
            except json.JSONDecodeError:
                payload = {"raw": raw}
        return exc.code, payload


def _tls_context_for_url(url: str):
    parsed = urlparse(url)
    if parsed.scheme.lower() != "https":
        return None
    if (parsed.hostname or "").lower() in {"127.0.0.1", "localhost", "::1"}:
        return ssl._create_unverified_context()
    cert_file = os.environ.get("SSL_CERT_FILE") or os.environ.get("TELLER_CLASSIFIER_TLS_CERT_FILE")
    if cert_file and os.path.isfile(cert_file):
        return ssl.create_default_context(cafile=cert_file)
    return ssl._create_unverified_context()


def _load_schema(schema_path_or_url: str):
    parsed = urlparse(schema_path_or_url)
    if parsed.scheme.lower() in {"http", "https"}:
        req = urllib.request.Request(schema_path_or_url, method="GET")
        context = _tls_context_for_url(schema_path_or_url)
        with urllib.request.urlopen(req, timeout=20, context=context) as resp:
            return json.load(resp)
    with open(schema_path_or_url, "r", encoding="utf-8") as fh:
        return json.load(fh)


def main() -> int:
    if len(sys.argv) != 6:
        raise SystemExit(
            "usage: delete_category_contract_check.py <schema_path> <base_url> <output_json_path> <write_token> <dast_run_id>"
        )
    schema_path, base_url, output_json_path, write_token, dast_run_id = sys.argv[1:6]
    schema = _load_schema(schema_path)
    delete_path = "/v1/categories/{nys_snw_category_id}"
    if delete_path not in schema.get("paths", {}):
        payload = {"status": "skipped", "reason": f"OpenAPI schema does not include {delete_path}"}
        with open(output_json_path, "w", encoding="utf-8") as fh:
            json.dump(payload, fh)
            fh.write("\n")
        print(json.dumps(payload))
        return 0
    seed_suffix = uuid.uuid4().hex[:8]
    seed_payload = {
        "level_1": "DAST",
        "level_1_name": "DAST Contract",
        "level_2": "Validation",
        "level_2_name": "Validation",
        "level_3": "Schemathesis",
        "level_4": f"Delete Contract {seed_suffix}",
        "categorization": f"Runtime Contract [{dast_run_id}] {seed_suffix}",
        "applicability": f"all-contract-{seed_suffix}",
    }
    preflight_status, preflight_payload = request_json("GET", f"{base_url}/v1/categories", write_token, None)
    if preflight_status != 200:
        payload = {
            "status": "skipped",
            "reason": f"Prerequisite endpoint GET /v1/categories unavailable ({preflight_status})",
            "payload": preflight_payload,
        }
        with open(output_json_path, "w", encoding="utf-8") as fh:
            json.dump(payload, fh)
            fh.write("\n")
        print(json.dumps(payload))
        return 0
    create_status, create_payload = request_json("POST", f"{base_url}/v1/categories", write_token, seed_payload)
    if create_status != 200 or not isinstance(create_payload, dict):
        raise SystemExit(
            f"Contract check failed: POST /v1/categories returned {create_status} with payload {create_payload}"
        )
    category_id = create_payload.get("nys_snw_category_id")
    if not isinstance(category_id, int):
        raise SystemExit(
            f"Contract check failed: missing integer nys_snw_category_id in create response {create_payload}"
        )
    delete_status, delete_payload = request_json("DELETE", f"{base_url}/v1/categories/{category_id}", write_token, None)
    if delete_status != 200 or not isinstance(delete_payload, dict):
        raise SystemExit(
            f"Contract check failed: DELETE /v1/categories/{{id}} returned {delete_status} with payload {delete_payload}"
        )
    if delete_payload.get("deleted") is not True or delete_payload.get("nys_snw_category_id") != category_id:
        raise SystemExit("Contract check failed: delete response payload contract mismatch")
    second_delete_status, second_delete_payload = request_json(
        "DELETE", f"{base_url}/v1/categories/{category_id}", write_token, None
    )
    if second_delete_status != 404:
        raise SystemExit("Contract check failed: second delete should return 404 for unknown category id")
    summary = {
        "status": "passed",
        "created_category_id": category_id,
        "first_delete_status": delete_status,
        "second_delete_status": second_delete_status,
        "second_delete_payload": second_delete_payload,
    }
    with open(output_json_path, "w", encoding="utf-8") as fh:
        json.dump(summary, fh)
        fh.write("\n")
    print(json.dumps(summary))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
