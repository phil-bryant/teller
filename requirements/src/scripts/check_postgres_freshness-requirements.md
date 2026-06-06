# Check PostgreSQL Freshness Requirements

## Scope

Applies to `src/scripts/check_postgres_freshness.py`.

R020  Statement: Collect PostgreSQL client/server freshness data with policy-aware gating.
Design: Discover client version via `psql --version`, optionally query server version, and evaluate minimum-version policies with a stale-component summary.
Tests:
- R020-T01: Verify client/server version parsing and stale-component gating for compliant and non-compliant versions.

R025  Statement: Evaluate CVE exposure using snapshot and policy inputs.
Design: Load snapshot/policy payloads, evaluate affected version ranges for client/server scopes, and mark gate failures when configured policy is violated.
Tests:
- R025-T01: Verify CVE matching, severity thresholds, stale snapshot handling, and fail-on-CVE behavior.

R240  Statement: Parse and compare semantic PostgreSQL versions.
Design: Implement semver parsing and ordering comparisons for policy checks.
Tests:
- R240-T01: Verify semver parse/compare helpers are available for version evaluation.

R241  Statement: Parse psql client/server version string formats.
Design: Parse psql --version and server_version_num formats into semver text.
Tests:
- R241-T01: Verify client/server version parsers are available for freshness checks.

R242  Statement: Decide whether current version meets minimum policy.
Design: Compare current and minimum versions with unknown safeguards.
Tests:
- R242-T01: Verify meets_minimum helper is available for minimum-policy checks.

R243  Statement: Normalize severity labels and apply threshold gating.
Design: Normalize severity text then evaluate threshold satisfaction.
Tests:
- R243-T01: Verify severity normalization helpers are available for CVE gating.

R244  Statement: Parse ISO datetime values safely.
Design: Parse ISO timestamp text with timezone-aware handling.
Tests:
- R244-T01: Verify ISO datetime parser is available for snapshot age checks.

R245  Statement: Evaluate version constraints, ranges, and any-range checks.
Design: Evaluate constraints/ranges for version vulnerability matching.
Tests:
- R245-T01: Verify constraint/range helpers are available for CVE matching.

R246  Statement: Read a JSON file into a dict payload or fallback.
Design: Load JSON from disk with absent/invalid fallback handling.
Tests:
- R246-T01: Verify JSON reader helper is available for snapshot/policy loading.

R247  Statement: Decide whether refreshed snapshot writing is needed.
Design: Compare refreshed vs existing snapshot payloads before writing.
Tests:
- R247-T01: Verify snapshot-write decision helper is available for refresh flow.

R248  Statement: Map CVE component text to client/server scope labels.
Design: Normalize component labels into evaluator scope identifiers.
Tests:
- R248-T01: Verify component-to-scope helper is available for finding classification.

R249  Statement: Map CVSS score to normalized severity bucket.
Design: Translate numeric score values into severity categories.
Tests:
- R249-T01: Verify score-to-severity helper is available for severity inference.

R250  Statement: Strip HTML markup from advisory text.
Design: Remove HTML tags before advisory parsing.
Tests:
- R250-T01: Verify HTML stripping helper is available for advisory parsing.

R251  Statement: Extract and validate PostgreSQL major versions.
Design: Extract major values and validate supported majors.
Tests:
- R251-T01: Verify major extraction/validation helpers are available for fetch guards.

R252  Statement: Fetch PostgreSQL security pages for a major version.
Design: Fetch trusted major-specific security page URLs.
Tests:
- R252-T01: Verify security-page fetch helper is available for snapshot generation.

R253  Statement: Build CVE snapshot payloads across PostgreSQL majors.
Design: Collect and normalize CVE entries from fetched security pages.
Tests:
- R253-T01: Verify CVE snapshot fetch helper is available for refresh workflow.

R254  Statement: Build initial CVE result skeleton payload.
Design: Initialize CVE result fields before evaluation.
Tests:
- R254-T01: Verify initial CVE result helper is available for evaluator setup.

R255  Statement: Load CVE policy from CLI arguments.
Design: Resolve policy defaults and policy file overrides from args.
Tests:
- R255-T01: Verify CVE policy loader helper is available for policy wiring.

R256  Statement: Refresh or load CVE snapshot data.
Design: Choose refresh path and load snapshot for evaluation.
Tests:
- R256-T01: Verify snapshot refresh/load helper is available for CVE evaluation.

R257  Statement: Mark policy failures on evaluation result.
Design: Set gate failure state and append policy diagnostics.
Tests:
- R257-T01: Verify policy-failure marker helper is available for gate signaling.

R258  Statement: Apply snapshot freshness windows to result.
Design: Evaluate snapshot age and stale policy behavior.
Tests:
- R258-T01: Verify snapshot freshness helper is available for stale policy checks.

R259  Statement: Collect CVE findings for evaluated version specs.
Design: Build findings across snapshot entries and target specs.
Tests:
- R259-T01: Verify findings helpers are available for CVE finding collection.

R260  Statement: Build server-version probe command arguments.
Design: Construct psql command for server-version probing.
Tests:
- R260-T01: Verify server command builder helper is available for server checks.

R261  Statement: Check client/server versions against freshness policy.
Design: Evaluate client and server version checks with warnings/errors.
Tests:
- R261-T01: Verify client/server check helpers are available for policy checks.

R262  Statement: Validate CVE entries from snapshot payload.
Design: Validate required CVE fields before evaluation.
Tests:
- R262-T01: Verify CVE entry validator helper is available for snapshot validation.

R263  Statement: Merge CVE counters into report summary.
Design: Merge CVE counters into aggregate report summary fields.
Tests:
- R263-T01: Verify CVE summary merge helper is available for summary consolidation.

R264  Statement: Build base human-readable report line set.
Design: Construct baseline report text lines before details.
Tests:
- R264-T01: Verify base report line helper is available for text formatting.

R265  Statement: Build initial client/server info blocks.
Design: Initialize client/server report dictionaries symmetrically.
Tests:
- R265-T01: Verify client/server info initializer helpers are available.

R266  Statement: Derive effective policy dict from parsed args.
Design: Resolve effective policy values from parser output.
Tests:
- R266-T01: Verify policy-from-args helper is available for policy derivation.

R267  Statement: Evaluate CVEs into findings and gate outcome.
Design: Apply snapshot+policy evidence to compute findings and gate state.
Tests:
- R267-T01: Verify evaluate_cves orchestrator is available for CVE evaluation.

R268  Statement: Run subprocess commands with timeout handling.
Design: Execute commands with captured output and timeout safeguards.
Tests:
- R268-T01: Verify run_command helper is available for process execution.

R269  Statement: Describe attempted server target string.
Design: Build human-readable server target descriptions for diagnostics.
Tests:
- R269-T01: Verify server-target descriptor helper is available for warnings.

R270  Statement: Assemble full PostgreSQL freshness report payload.
Design: Combine version checks, CVE checks, and summary payload sections.
Tests:
- R270-T01: Verify build_report orchestrator is available for report assembly.

R271  Statement: Render human-readable PostgreSQL freshness report.
Design: Render report payload into operator-readable text output.
Tests:
- R271-T01: Verify format_text_report helper is available for text report output.

R272  Statement: Parse PostgreSQL freshness CLI arguments.
Design: Define parser options for version/CVE checks and outputs.
Tests:
- R272-T01: Verify parse_args helper is available for CLI option parsing.

R273  Statement: Orchestrate PostgreSQL freshness run and exit policy.
Design: Execute full run, persist artifacts, and apply exit gates.
Tests:
- R273-T01: Verify main entrypoint is available for orchestration policy.
