# Install Prerequisites Requirements

## Scope

Applies to `01_install_prerequisites.sh` and any successor installer for local macOS setup.

R001  Statement: Run on macOS with `bash` and fail fast.
Design: Use `set -e`; return non-zero on unrecoverable failures.
Tests:
- R001-T01: Force a failing install step and verify non-zero exit.

R005  Statement: Verify Homebrew exists before package actions.
Design: Check `brew` on `PATH`; print install guidance when missing.
Tests:
- R005-T01: Run without `brew` in `PATH` and verify clear failure message.

R010  Statement: Ensure `1psa` is available on `PATH`.
Design: If missing, build and install from sibling source tree `../1psa`.
Constraints:
- Clone from `https://github.com/phil-bryant/1psa.git` when source is absent.
- Require `Makefile` in source tree before build/install.
Tests:
- R010-T01: On a machine without `1psa`, verify clone/build/install completes and `command -v 1psa` succeeds.

R012  Statement: Ensure `1psa` build prerequisites are available.
Design: Install missing `go` and `git` via Homebrew before clone/build paths.
Tests:
- R012-T01: Run without `go` and verify script installs it before `1psa` build.
- R012-T02: Run without `git` and verify script installs it before clone/build operations.

R015  Statement: Install `1psa` via upstream Makefile targets.
Design: Run `make` then `sudo make install` from `../1psa`.
Rationale: Keep install behavior aligned with upstream project conventions.
Tests:
- R015-T01: Verify local build produces executable `../1psa/bin/1psa`.
- R015-T02: Verify installed `1psa` resolves on `PATH` after install.

R020  Statement: Source sudo credential via local `1psa` item lookup.
Design: Pipe `../1psa/bin/1psa -f <item> <field>` to `sudo -S make install`.
Constraints:
- Default `<item>` and `<field>` are `odus`.
- Allow override via `PSA_INSTALL_SUDO_ITEM`.
Tests:
- R020-T01: Override `PSA_INSTALL_SUDO_ITEM` and verify install path still works.

R025  Statement: Ensure pg_install is installed and verified.
Design: Require `pg_install`; clone from sibling source tree `../pg_install` when absent.
Constraints:
- Clone from `https://github.com/phil-bryant/pg_install` when source is absent.
- Verify with `test -d ../pg_install/.git`.
Tests:
- R025-T01: Remove `../pg_install` and verify installer restores the repository clone.

R030  Statement: Ensure git is available for clone operations.
Design: Require `git`; install via Homebrew if absent before repo clone actions.
Tests:
- R030-T01: Run without `git` and verify installer installs it before `pg_install` clone.

R035  Statement: Print explicit status for each prerequisite phase.
Design: Emit installed/installing/success/failure lines for Homebrew, `1psa`, and `pg_install`.
Tests:
- R035-T01: Run installer and verify all major phases print status lines.

R040  Statement: Keep installer idempotent across reruns.
Design: Skip installs when dependencies already satisfy checks.
Tests:
- R040-T01: Run installer twice and verify second run performs no unnecessary installs.

R045  Statement: Avoid storing credentials in repository files.
Constraints:
- No hardcoded secrets in script.
- Rely on user-managed `~/.1psa` and secure `1psa` lookups at runtime.
Tests:
- R045-T01: Inspect script text and verify no embedded secret values.

R050  Statement: Print final readiness guidance for local setup.
Design: End with success banner and example path references for `../1psa` and `../pg_install`, plus optional PLCrashReporter smoke verification entrypoint (`./14_verify_macos_crash_test.sh`, run separately—not from other numbered scripts).
Tests:
- R050-T01: On successful run, verify final message includes `../1psa` and `../pg_install`.
- R050-T02: On successful run, verify final guidance includes `./14_verify_macos_crash_test.sh`.

R055  Statement: Ensure shell unit-test runner dependency is available.
Design: Install Homebrew formula `bats-core` and verify `bats` resolves on `PATH`.
Tests:
- R055-T01: Run without `bats` and verify installer installs `bats-core`.
- R055-T02: Rerun with `bats` already available and verify no reinstall occurs.

R060  Statement: Ensure Xcode first-launch prerequisites are satisfied.
Design: Verify `xcodebuild` exists and run first-launch initialization when required.
Constraints:
- Fail with clear guidance when `xcodebuild` is unavailable.
- Re-check first-launch status after initialization and fail if still incomplete.
Tests:
- R060-T01: Run on a machine without first-launch complete and verify initialization is attempted.
- R060-T02: Run on a machine already initialized and verify the phase is skipped.

R065  Statement: Use 1psa-provided sudo credential for privileged Xcode initialization.
Design: Pipe local `../1psa/bin/1psa` item lookup to `sudo -S` for first-launch/license commands.
Constraints:
- Reuse `PSA_INSTALL_SUDO_ITEM` for credential source.
- Avoid interactive password prompts in non-interactive runs.
Tests:
- R065-T01: Verify first-launch setup command uses piped credential input.
- R065-T02: Verify license-accept path also uses piped credential input when needed.

R070  Statement: Ensure OWASP ZAP local CLI tooling is installed.
Design: Install Homebrew cask `zap` when ZAP CLI wrapper is missing.
Constraints:
- Prefer existing install when `ZAP.app` CLI wrapper is already present.
- Use Homebrew cask install path compatible with macOS applications (`/Applications/ZAP.app`).
Tests:
- R070-T01: Run on machine without ZAP and verify installer runs `brew install --cask zap`.
- R070-T02: Rerun with ZAP already present and verify install phase is skipped.

R075  Statement: Verify ZAP CLI executable path after installation.
Design: Require executable wrapper at `/Applications/ZAP.app/Contents/MacOS/ZAP.sh` (or equivalent configured path) and fail with guidance if missing.
Tests:
- R075-T01: After successful install, verify executable path check passes.
- R075-T02: Simulate missing wrapper after install and verify clear failure message.

R079  Statement: Ensure Perl runtime is available for pgTAP Perl tooling.
Design: Install Homebrew formula `perl` when `perl` is unavailable on `PATH`.
Tests:
- R079-T01: Run without `perl` and verify installer installs `perl`.
- R079-T02: Rerun with `perl` already available and verify no reinstall occurs.

R080  Statement: Ensure cpanminus is available for Perl module installs.
Design: Install Homebrew formula `cpanminus` and verify `cpanm` resolves on `PATH`.
Tests:
- R080-T01: Run without `cpanm` and verify installer installs `cpanminus`.
- R080-T02: Rerun with `cpanm` already available and verify no reinstall occurs.

R085  Statement: Install pgTAP from upstream source when runner is missing.
Design: If `pg_prove` is unavailable, clone `https://github.com/theory/pgtap.git` into sibling `../pgtap`, then run `make` and `make install`.
Constraints:
- Skip clone/build/install when `pg_prove` resolves on `PATH` or at `~/perl5/bin/pg_prove`.
- Require `Makefile` in `../pgtap` before build/install.
Tests:
- R085-T01: Run without `pg_prove` and verify installer clones `../pgtap` and runs `make` then `make install`.
- R085-T02: Rerun with `pg_prove` already available and verify pgtap source build/install path is skipped.

R090  Statement: Ensure Perl pgTAP source handler installs to user-local Perl prefix.
Design: If `pg_prove` is unavailable on `PATH` and at `~/perl5/bin/pg_prove`, run `cpanm --local-lib="$HOME/perl5" --reinstall TAP::Parser::SourceHandler::pgTAP`.
Constraints:
- Treat `~/perl5/bin/pg_prove` as the canonical installed location even when not on `PATH`.
Tests:
- R090-T01: Simulate missing runner and verify installer invokes `cpanm --local-lib="$HOME/perl5" --reinstall TAP::Parser::SourceHandler::pgTAP`.
- R090-T02: Simulate runner already present at `~/perl5/bin/pg_prove` and verify cpanm install path is skipped.

R095  Statement: Ensure ClamAV command-line scanner is available for security checks.
Design: Install Homebrew formula `clamav` and verify `clamscan` resolves on `PATH`.
Tests:
- R095-T01: Run without `clamscan` and verify installer installs `clamav`.
- R095-T02: Rerun with `clamscan` already available and verify no reinstall occurs.

R100  Statement: Ensure ShellCheck command-line scanner is available for SAST shell analysis.
Design: Install Homebrew formula `shellcheck` and verify `shellcheck` resolves on `PATH`.
Tests:
- R100-T01: Run without `shellcheck` and verify installer installs `shellcheck`.
- R100-T02: Rerun with `shellcheck` already available and verify no reinstall occurs.

R105  Statement: Ensure gitleaks command-line scanner is available for SAST secret leak analysis.
Design: Install Homebrew formula `gitleaks` and verify `gitleaks` resolves on `PATH`.
Tests:
- R105-T01: Run without `gitleaks` and verify installer installs `gitleaks`.
- R105-T02: Rerun with `gitleaks` already available and verify no reinstall occurs.

## Changelog

- 2026-05-12: R050 guidance references `./14_verify_macos_crash_test.sh` (standalone; not chained from other numbered scripts).
- 2026-05-07: Updated R050 guidance to include optional PLCrashReporter smoke verification entrypoint.
- 2026-04-23: Added R055 to require `bats-core` installation for shell unit-test support.
- 2026-04-26: Added R095 to require Homebrew `clamav` (`clamscan`) for repository malware scans.
- 2026-05-09: Added R100 to require Homebrew `shellcheck` for shell-script SAST scanning.
- 2026-05-09: Added R105 to require Homebrew `gitleaks` for secret-leak scanning.
- 2026-04-26: Added R079 to require Homebrew `perl` before cpanminus-managed pgTAP Perl tooling.
- 2026-04-26: Reworked pgTAP prerequisites: R080 (`cpanminus`), R085 (build/install `../pgtap`), and R090 (user-local `cpanm` source handler install).
- 2026-04-24: Added R060 and R065 to cover Xcode first-launch readiness and credentialed sudo flow.
- 2026-04-24: Added R070 and R075 to require local OWASP ZAP cask installation and CLI path verification.
- 2026-04-07: Added R012 for Go/Git bootstrap prerequisites used by `1psa` install flow.
- 2026-04-06: Restored full standalone installer requirements (not split-index form).
- 2026-04-11: Replaced SQL/Azure CLI requirements with `pg_install` prerequisite and updated readiness guidance.
