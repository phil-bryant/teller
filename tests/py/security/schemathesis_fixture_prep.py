#!/usr/bin/env python3
import json
import os
import ssl
import sys
import urllib.request
from urllib.parse import urlparse


def fetch_json(url: str, write_token: str):
    req = urllib.request.Request(url, headers={"X-Teller-Write-Token": write_token}, method="GET")
    with urllib.request.urlopen(req, timeout=20, context=_tls_context_for_url(url)) as resp:
        return json.load(resp)


def post_json(url: str, write_token: str, payload: dict):
    req = urllib.request.Request(
        url,
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json", "X-Teller-Write-Token": write_token},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=20, context=_tls_context_for_url(url)) as resp:
        return json.load(resp)


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


def set_path_param_example(paths, path: str, method: str, param_name: str, value):
    operation = paths.get(path, {}).get(method, {})
    for param in operation.get("parameters", []):
        if param.get("in") == "path" and param.get("name") == param_name:
            param["example"] = value


def set_path_param_enum(paths, path: str, method: str, param_name: str, values):
    operation = paths.get(path, {}).get(method, {})
    for param in operation.get("parameters", []):
        if param.get("in") == "path" and param.get("name") == param_name:
            schema_obj = param.get("schema")
            if isinstance(schema_obj, dict):
                schema_obj["enum"] = values
            if values:
                param["example"] = values[0]


def set_json_body_example(paths, path: str, method: str, example):
    operation = paths.get(path, {}).get(method, {})
    content = operation.get("requestBody", {}).get("content", {})
    app_json = content.get("application/json")
    if isinstance(app_json, dict):
        app_json["example"] = example


def set_component_string_min_length(schema: dict, component_name: str, field_names: list[str], min_length: int):
    components = schema.get("components", {})
    if not isinstance(components, dict):
        return
    schemas = components.get("schemas", {})
    if not isinstance(schemas, dict):
        return
    component = schemas.get(component_name)
    if not isinstance(component, dict):
        return
    properties = component.get("properties", {})
    if not isinstance(properties, dict):
        return
    for field_name in field_names:
        prop = properties.get(field_name)
        if not isinstance(prop, dict):
            continue
        if prop.get("type") == "string":
            prop["minLength"] = min_length
            continue
        any_of = prop.get("anyOf")
        if isinstance(any_of, list):
            for variant in any_of:
                if isinstance(variant, dict) and variant.get("type") == "string":
                    variant["minLength"] = min_length


def tighten_matchy_search_query_params(paths: dict):
    operation = paths.get("/v1/matchy/messages/search", {}).get("get", {})
    parameters = operation.get("parameters", [])
    if not isinstance(parameters, list):
        return
    for param in parameters:
        if not isinstance(param, dict):
            continue
        if param.get("in") != "query":
            continue
        name = param.get("name")
        schema_obj = param.get("schema")
        if not isinstance(schema_obj, dict):
            continue
        if name in {"subject", "sender", "body"}:
            schema_obj["minLength"] = max(int(schema_obj.get("minLength", 0) or 0), 1)
        if name == "subject":
            # FastAPI enforces "at least one structured criterion", which OpenAPI cannot express as
            # "one-of these query params must be present". Require `subject` in the generated
            # Schemathesis fixture to avoid schema-valid empty requests that the API correctly rejects.
            param["required"] = True
        if name in {"start_date", "end_date"}:
            # The API treats empty/"null" date values as no-op criteria and can return 422 when
            # no effective structured filters remain. Keep Schemathesis focused on meaningful
            # structured date inputs so schema-valid requests align with success-path behavior.
            schema_obj["minLength"] = 10
            schema_obj["maxLength"] = 10
            schema_obj["pattern"] = r"^[0-9]{4}-[0-9]{2}-[0-9]{2}$"


def main() -> int:
    if len(sys.argv) != 7:
        raise SystemExit(
            "usage: schemathesis_fixture_prep.py <openapi_url> <base_url> <out_path> <write_token> <matchy_seed_path> <dast_run_id>"
        )
    openapi_url, base_url, out_path, write_token, matchy_seed_path, dast_run_id = sys.argv[1:7]
    schema = fetch_json(openapi_url, write_token)
    category_id = None
    transaction_id = None
    delete_seed_ids = []
    match_ids = []
    match_override_email = None
    if matchy_seed_path:
        try:
            with open(matchy_seed_path, "r", encoding="utf-8") as fh:
                seed_payload = json.load(fh)
            if isinstance(seed_payload, dict):
                for value in seed_payload.get("match_ids", []):
                    if isinstance(value, int):
                        match_ids.append(value)
                seeded_override_email = seed_payload.get("override_email_message_id")
                if isinstance(seeded_override_email, str) and seeded_override_email:
                    match_override_email = seeded_override_email
        except Exception:
            pass
    category_text_fields = [
        "level_1",
        "level_1_name",
        "level_2",
        "level_2_name",
        "level_3",
        "level_4",
        "categorization",
        "applicability",
    ]
    set_component_string_min_length(schema, "CategoryCreateMutation", category_text_fields, 1)
    set_component_string_min_length(schema, "CategoryUpdateMutation", category_text_fields, 1)
    try:
        categories = fetch_json(f"{base_url}/v1/categories", write_token)
        if isinstance(categories, list) and categories:
            category_id = categories[0].get("nys_snw_category_id")
    except Exception:
        pass
    if category_id is None:
        try:
            created = post_json(
                f"{base_url}/v1/categories",
                write_token,
                {
                    "level_1": "DAST",
                    "level_1_name": "DAST Seed",
                    "level_2": "Validation",
                    "level_2_name": "Validation",
                    "level_3": "Schemathesis",
                    "level_4": "Seed",
                    "categorization": f"Runtime [{dast_run_id}]",
                    "applicability": "all",
                },
            )
            category_id = created.get("nys_snw_category_id")
        except Exception:
            pass

    def create_seed_category(seed_suffix: str):
        try:
            created = post_json(
                f"{base_url}/v1/categories",
                write_token,
                {
                    "level_1": "DAST",
                    "level_1_name": "DAST Seed",
                    "level_2": "Validation",
                    "level_2_name": "Validation",
                    "level_3": "Schemathesis",
                    "level_4": f"Delete Seed {seed_suffix}",
                    "categorization": f"Runtime [{dast_run_id}] {seed_suffix}",
                    "applicability": f"all-{seed_suffix}",
                },
            )
            return created.get("nys_snw_category_id")
        except Exception:
            return None

    for idx in range(32):
        seed_id = create_seed_category(str(idx))
        if isinstance(seed_id, int):
            delete_seed_ids.append(seed_id)
    try:
        tx_payload = fetch_json(f"{base_url}/v1/transactions?limit=1&offset=0", write_token)
        items = tx_payload.get("items", []) if isinstance(tx_payload, dict) else []
        if items:
            transaction_id = items[0].get("transaction_id")
    except Exception:
        pass
    if not match_ids:
        try:
            review_payload = fetch_json(f"{base_url}/v1/matchy/review?limit=25&offset=0", write_token)
            review_items = review_payload.get("items", []) if isinstance(review_payload, dict) else []
            for item in review_items:
                if isinstance(item, dict) and isinstance(item.get("match_id"), int):
                    match_ids.append(item["match_id"])
                    email_value = item.get("email_message_id")
                    if match_override_email is None and isinstance(email_value, str) and email_value:
                        match_override_email = email_value
        except Exception:
            pass
    paths = schema.get("paths", {})
    if isinstance(paths, dict):
        tighten_matchy_search_query_params(paths)
    if category_id is not None:
        set_path_param_example(paths, "/v1/categories/{nys_snw_category_id}", "put", "nys_snw_category_id", category_id)
    if delete_seed_ids:
        set_path_param_enum(paths, "/v1/categories/{nys_snw_category_id}", "delete", "nys_snw_category_id", delete_seed_ids)
    elif category_id is not None:
        set_path_param_example(paths, "/v1/categories/{nys_snw_category_id}", "delete", "nys_snw_category_id", category_id)
    if transaction_id is not None:
        set_path_param_example(
            paths, "/v1/transactions/{transaction_id}/classification", "put", "transaction_id", transaction_id
        )
    if transaction_id is not None and category_id is not None:
        set_json_body_example(
            paths,
            "/v1/transactions/{transaction_id}/classification",
            "put",
            {"nys_snw_category_id": category_id},
        )
        set_json_body_example(
            paths,
            "/v1/transactions/classifications",
            "post",
            {"updates": [{"transaction_id": transaction_id, "nys_snw_category_id": category_id}]},
        )
    if match_ids:
        set_path_param_enum(paths, "/v1/matchy/matches/{match_id}/confirm", "put", "match_id", match_ids)
        set_path_param_enum(paths, "/v1/matchy/matches/{match_id}/no-email", "put", "match_id", match_ids)
        set_path_param_enum(paths, "/v1/matchy/matches/{match_id}/clear", "put", "match_id", match_ids)
        set_path_param_enum(paths, "/v1/matchy/matches/{match_id}/override", "put", "match_id", match_ids)
        set_json_body_example(
            paths,
            "/v1/matchy/matches/{match_id}/override",
            "put",
            {
                "email_message_id": match_override_email or "msg_seeded_override_1",
                "note": "Schemathesis seeded override",
            },
        )
    if transaction_id is not None and match_override_email:
        set_path_param_example(
            paths,
            "/v1/matchy/transactions/{transaction_id}/confirm-candidate",
            "put",
            "transaction_id",
            transaction_id,
        )
        set_path_param_example(
            paths,
            "/v1/matchy/transactions/{transaction_id}/override-candidate",
            "put",
            "transaction_id",
            transaction_id,
        )
        set_path_param_example(
            paths,
            "/v1/matchy/transactions/{transaction_id}/override",
            "put",
            "transaction_id",
            transaction_id,
        )
        candidate_body = {
            "email_message_id": match_override_email,
            "note": "Schemathesis seeded candidate",
        }
        set_json_body_example(
            paths,
            "/v1/matchy/transactions/{transaction_id}/confirm-candidate",
            "put",
            candidate_body,
        )
        set_json_body_example(
            paths,
            "/v1/matchy/transactions/{transaction_id}/override-candidate",
            "put",
            candidate_body,
        )
        set_json_body_example(
            paths,
            "/v1/matchy/transactions/{transaction_id}/override",
            "put",
            {
                "email_message_id": match_override_email,
                "note": "Schemathesis seeded override",
            },
        )
    with open(out_path, "w", encoding="utf-8") as fh:
        json.dump(schema, fh)
        fh.write("\n")
    print(
        json.dumps(
            {
                "fixture": out_path,
                "seeded_category_id": category_id,
                "seeded_transaction_id": transaction_id,
                "delete_seed_ids": delete_seed_ids,
                "match_ids": match_ids,
                "match_override_email": match_override_email,
            }
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
