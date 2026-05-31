# Shell Unit Test Matrix

This directory contains `bats-core` unit tests for repository shell scripts.

## Tier 1 (implemented first)

- `t04_run_requirements_traceability_tests.bats` -> `t04_run_requirements_traceability_tests.sh`
  - Requirement IDs: `R001`, `R005`, `R010`, `R015`, `R020`, `R025`, `R030`, `R035`
- `01_install_prerequisites.bats` -> `01_install_prerequisites.sh`
  - Requirement IDs: `R005`, `R010`, `R012`, `R020`, `R025`, `R035`, `R040`, `R050`
- `02_create_venv.bats` -> `02_create_venv.sh`
  - Requirement IDs: `R005`, `R010`, `R015`, `R020`, `R025`, `R030`, `R035`, `R040`
- `03_prepare_supply_chain_integrity.bats` -> `03_prepare_supply_chain_integrity.sh`
  - Requirement IDs: `R001`, `R005`, `R010`, `R015`
- `99_restore_database.bats` -> `99_restore_database.sh`
  - Requirement IDs: `R005`, `R010`, `R015`, `R020`, `R025`, `R030`, `R040`, `R045`, `R070`

## Tier 2 (implemented after Tier 1 baseline)

- `97_backup_database.bats` -> `97_backup_database.sh`
  - Requirement IDs: `R005`, `R010`, `R015`, `R020`, `R025`, `R030`, `R035`
- `98_destroy_database.bats` -> `98_destroy_database.sh`
  - Requirement IDs: `R005`, `R010`, `R015`, `R020`, `R025`
- `t07_run_shell_unit_tests.bats` -> `t07_run_shell_unit_tests.sh`
  - Requirement IDs: `R001`, `R005`, `R010`, `R015`, `R020`
- `10_run_classification_macos_ui.bats` -> `10_run_classification_macos_ui.sh`
  - Wrapper contract test (forwarding and package-path composition)

## Notes

- Tests avoid live network and database dependencies by using command stubs.
- Integration scripts (`07`, `08`, `10`, `18`) remain out of unit scope by design.
