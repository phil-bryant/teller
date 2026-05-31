#!/usr/bin/env bats

@test "sqlite schema sets foreign key pragma" {
  #R001-T01: Parse create_database.sql and verify foreign-key pragma exists.
  #R001: SQLite deploy enables foreign-key enforcement before schema creation.
  run rg -n "PRAGMA foreign_keys = ON;" src/sql/sqlite/create_database.sql
  [ "$status" -eq 0 ]
}

@test "sqlite schema defines ingest graph tables" {
  #R005-T01: Parse create_database.sql and verify core ingest table names are declared.
  #R005: SQLite deploy defines the core institution/account/identity graph required by ingest.
  run rg -n "CREATE TABLE IF NOT EXISTS (institution|account|identity)" src/sql/sqlite/create_database.sql
  [ "$status" -eq 0 ]
}

@test "sqlite schema defines classification and match tables" {
  #R010-T01: Parse create_database.sql and verify classification + match-review table declarations exist.
  #R010: SQLite deploy defines transaction, classification, and match-review tables required by classification API runtime.
  run rg -n "CREATE TABLE IF NOT EXISTS (\"transaction\"|nys_snw_category|transaction_nys_snw_category|transaction_email_match)" src/sql/sqlite/create_database.sql
  [ "$status" -eq 0 ]
}

@test "sqlite schema defines transaction info view" {
  #R015-T01: Parse create_database.sql and verify transaction_info_view DDL is present.
  #R015: SQLite deploy materializes transaction list view required by verification and runtime queries.
  run rg -n "CREATE VIEW IF NOT EXISTS transaction_info_view AS" src/sql/sqlite/create_database.sql
  [ "$status" -eq 0 ]
}
