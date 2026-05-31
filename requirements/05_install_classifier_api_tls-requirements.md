# Local Classifier API TLS Install Requirements

## Scope

Applies to `05_install_classifier_api_tls.sh`.

R001  Statement: Install classifier TLS assets at deterministic local paths.
Design: Resolve `TELLER_CLASSIFIER_TLS_CERT_FILE` / `TELLER_CLASSIFIER_TLS_KEY_FILE` with defaults under `~/.teller` and print selected paths before generation.
Tests:
- R001-T01: Verify script references `classifier-localhost-cert.pem` and `classifier-localhost-key.pem` defaults.

R005  Statement: Preserve existing mkcert-generated cert decisions by default.
Design: If both target cert and key files already exist and are non-empty, print a checking summary and exit with an explicit already-installed message before any generate/install wording. Replace legacy self-signed material automatically; honor `TELLER_CLASSIFIER_TLS_FORCE_REGENERATE=true` for explicit regeneration.
Tests:
- R005-T01: Verify script includes an explicit already-installed early-return path.
- R005-T02: Verify generate/install messaging appears only after the already-installed check.
- R005-T03: Verify legacy self-signed replacement path is present.

R010  Statement: Require mkcert for local classifier TLS generation.
Design: Fail clearly when `mkcert` is unavailable and direct the operator to run `./01_install_prerequisites.sh`; generate localhost+loopback SAN cert/key only via `mkcert -cert-file ... -key-file ... localhost 127.0.0.1 ::1` after best-effort `mkcert -install`.
Tests:
- R010-T01: Verify script checks for `mkcert` and invokes `mkcert -cert-file ... -key-file ... localhost 127.0.0.1 ::1`.
- R010-T02: Verify missing `mkcert` exits non-zero with guidance to run `./01_install_prerequisites.sh`.
- R010-T03: Verify script does not include an OpenSSL self-signed generation path.

## Changelog

- 2026-05-26: Require mkcert-only generation; remove OpenSSL fallback.
- 2026-05-26: Require checking/no-op messaging before any generate banner on reruns.
- 2026-05-25: Initial requirements for control-plane slot `05` TLS install script.
