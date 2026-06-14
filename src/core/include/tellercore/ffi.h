// #R001: Module-level traceability anchor.
#ifndef TELLERCORE_FFI_H
#define TELLERCORE_FFI_H

#ifdef __cplusplus
extern "C" {
#endif

// JSON-command FFI over the teller core, mirroring classycore's contract so the
// same platform adapters (Swift, matchy) can target either core.
//
// All functions return a heap-allocated UTF-8 JSON C string that the caller
// must release with teller_core_free. A null return indicates allocation
// failure only; logical errors come back inside the JSON envelope.
//
// open(config_json): opens the process-wide core against a database.
//   config: {"sqlite_path": "...", "sqlcipher_key": "...", "target": "sqlite|local|managed",
//            "bootstrap_ddl_path": "...", "enable_mailcart": true}
//   Omitted fields fall back to teller_db_profile resolution.
//   -> {"ok": true} | {"ok": false, "status": <int>, "detail": "..."}
//
// invoke(request_json): {"op": "<operation>", "args": { ... }}
//   ops: "persist", "resolve_profile", "fetch_message", "search_messages".
//   success -> {"ok": true, "body": <result>}
//   error   -> {"ok": false, "status": <int>, "detail": "..."}
char* teller_core_open(const char* config_json);
char* teller_core_invoke(const char* request_json);
void teller_core_free(char* ptr);
char* teller_core_close(void);

#ifdef __cplusplus
}
#endif

#endif // TELLERCORE_FFI_H
