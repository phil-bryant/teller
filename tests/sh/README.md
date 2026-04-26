# Shell Unit Test Matrix

This directory contains `bats-core` unit tests for repository shell scripts.

## Tier 1 (implemented first)

- `00_verify_requirements_traceability.bats` -> `00_verify_requirements_traceability.sh`
  - Requirement IDs: `R001`, `R005`, `R010`, `R015`, `R020`, `R025`, `R030`, `R035`
- `01_install_prerequisites.bats` -> `01_install_prerequisites.sh`
  - Requirement IDs: `R005`, `R010`, `R012`, `R020`, `R025`, `R035`, `R040`, `R050`
- `02_create_venv.bats` -> `02_create_venv.sh`
  - Requirement IDs: `R005`, `R010`, `R015`, `R020`, `R025`, `R030`, `R035`, `R040`
- `10_configure_teller_io.bats` -> `10_configure_teller_io.sh`
  - Requirement IDs: `R005`, `R010`, `R015`, `R020`, `R025`, `R035`, `R040`
- `11_run_teller-connect-ui.bats` -> `11_run_teller-connect-ui.sh`
  - Requirement IDs: `R050`, `R055`, `R060`, `R070`, `R075`, `R080`, `R085`, `R090`
- `99_restore_database.bats` -> `99_restore_database.sh`
  - Requirement IDs: `R005`, `R010`, `R015`, `R020`, `R025`, `R030`, `R040`, `R045`

## Tier 2 (implemented after Tier 1 baseline)

- `97_backup_database.bats` -> `97_backup_database.sh`
  - Requirement IDs: `R005`, `R010`, `R015`, `R020`, `R025`, `R030`, `R035`
- `98_destroy_database.bats` -> `98_destroy_database.sh`
  - Requirement IDs: `R005`, `R010`, `R015`, `R020`, `R025`
- `05_run_unit_tests.bats` -> `05_run_unit_tests.sh`
  - Requirement IDs: `R001`, `R005`, `R010`, `R015`, `R020`
- `14_run_transaction_classification_macos-ui.bats` -> `16_run_classification_macos-ui.sh`
  - Wrapper contract test (forwarding and package-path composition)

## Notes

- Tests avoid live network and database dependencies by using command stubs.
- Integration scripts (`05`, `06`, `08`, `15`) remain out of unit scope by design.
