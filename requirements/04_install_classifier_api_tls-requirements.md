# Local Classifier API TLS Install Requirements

## Scope

Applies to `04_install_classifier_api_tls.sh`.

R001  Statement: Install classifier TLS assets at deterministic local paths.
Design: Resolve `TELLER_CLASSIFIER_TLS_CERT_FILE` / `TELLER_CLASSIFIER_TLS_KEY_FILE` with defaults under `~/.teller` and print selected paths before generation.
Tests:
- R001-T01: Verify script references `classifier-localhost-cert.pem` and `classifier-localhost-key.pem` defaults.

R005  Statement: Preserve existing local cert decisions by default.
Design: If both target cert and key files already exist and are non-empty, emit a no-op success message and exit without regeneration.
Tests:
- R005-T01: Verify script includes an explicit already-present early-return path.

R010  Statement: Prefer trusted local cert generation when mkcert is available.
Design: Detect `mkcert`, run local CA install best-effort, and generate localhost+loopback SAN cert/key at target paths.
Tests:
- R010-T01: Verify script checks for `mkcert` and invokes `mkcert -cert-file ... -key-file ... localhost 127.0.0.1 ::1`.

R015  Statement: Provide an OpenSSL fallback when mkcert is unavailable.
Design: Detect `openssl` and generate a self-signed localhost certificate with SANs for `localhost`, `127.0.0.1`, and `::1`; fail clearly if neither tool exists.
Tests:
- R015-T01: Verify script includes OpenSSL detection and `openssl req` generation path.

## Changelog

- 2026-05-26: Renamed from `04_bootstrap_local_classifier_tls.sh` to `04_install_classifier_api_tls.sh`.
- 2026-05-25: Initial requirements for control-plane slot `04` TLS install script.
