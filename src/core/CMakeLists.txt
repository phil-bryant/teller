cmake_minimum_required(VERSION 3.24)
project(tellercore LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

if(APPLE AND NOT CMAKE_OSX_DEPLOYMENT_TARGET)
  set(CMAKE_OSX_DEPLOYMENT_TARGET "14.0" CACHE STRING "" FORCE)
endif()

option(TELLERCORE_BUILD_TESTS "Build tellercore unit tests" ON)
option(TELLERCORE_BUILD_TOOLS "Build oracle runner + ingest CLI" ON)
option(TELLERCORE_SANITIZE "Build with ASan+UBSan" OFF)
# OFF leaves the core without the Mailcart/HTTP client and ingest CLI.
option(TELLERCORE_ENABLE_HTTP "Build the Mailcart HTTP client + Teller API ingest" ON)
# libpq backend for local Postgres and Supabase-managed Postgres profiles.
option(TELLERCORE_ENABLE_POSTGRES "Build the libpq Postgres/Supabase backend" ON)

if(NOT CMAKE_BUILD_TYPE)
  set(CMAKE_BUILD_TYPE RelWithDebInfo)
endif()

add_compile_options(-Wall -Wextra -Wpedantic -Werror)
if(TELLERCORE_SANITIZE)
  add_compile_options(-fsanitize=address,undefined -fno-omit-frame-pointer)
  add_link_options(-fsanitize=address,undefined)
endif()

# ---- SQLCipher (brew on macOS desktop) ----
find_path(SQLCIPHER_INCLUDE_DIR sqlcipher/sqlite3.h
  HINTS ${TELLERCORE_SQLCIPHER_ROOT} /opt/homebrew/opt/sqlcipher /usr/local/opt/sqlcipher
  PATH_SUFFIXES include)
find_library(SQLCIPHER_LIBRARY
  NAMES sqlcipher
  HINTS ${TELLERCORE_SQLCIPHER_ROOT} /opt/homebrew/opt/sqlcipher /usr/local/opt/sqlcipher
  PATH_SUFFIXES lib)
if(NOT SQLCIPHER_INCLUDE_DIR OR NOT SQLCIPHER_LIBRARY)
  message(FATAL_ERROR "SQLCipher not found. brew install sqlcipher or set TELLERCORE_SQLCIPHER_ROOT")
endif()

find_package(Threads REQUIRED)

# ---- libpq (brew keg-only on macOS; libpq-dev on Linux) ----
if(TELLERCORE_ENABLE_POSTGRES)
  find_path(LIBPQ_INCLUDE_DIR libpq-fe.h
    HINTS ${TELLERCORE_LIBPQ_ROOT} /opt/homebrew/opt/libpq /usr/local/opt/libpq
    PATH_SUFFIXES include include/postgresql)
  find_library(LIBPQ_LIBRARY
    NAMES pq
    HINTS ${TELLERCORE_LIBPQ_ROOT} /opt/homebrew/opt/libpq /usr/local/opt/libpq
    PATH_SUFFIXES lib)
  if(NOT LIBPQ_INCLUDE_DIR OR NOT LIBPQ_LIBRARY)
    message(FATAL_ERROR
      "libpq not found. brew install libpq (macOS) / apt-get install libpq-dev (Linux), "
      "set TELLERCORE_LIBPQ_ROOT, or configure with -DTELLERCORE_ENABLE_POSTGRES=OFF")
  endif()
endif()

include(FetchContent)
FetchContent_Declare(nlohmann_json
  URL https://github.com/nlohmann/json/releases/download/v3.11.3/json.tar.xz
  DOWNLOAD_EXTRACT_TIMESTAMP ON)
FetchContent_MakeAvailable(nlohmann_json)

if(TELLERCORE_ENABLE_HTTP)
  find_package(OpenSSL REQUIRED)
  set(HTTPLIB_USE_BROTLI_IF_AVAILABLE OFF CACHE BOOL "" FORCE)
  set(HTTPLIB_USE_ZSTD_IF_AVAILABLE OFF CACHE BOOL "" FORCE)
  FetchContent_Declare(httplib
    URL https://github.com/yhirose/cpp-httplib/archive/refs/tags/v0.18.3.tar.gz
    DOWNLOAD_EXTRACT_TIMESTAMP ON)
  FetchContent_MakeAvailable(httplib)
endif()

add_library(tellercore STATIC
  src/onepsa.cpp
  src/profile.cpp
  src/db.cpp
  src/db_sqlite.cpp
  src/json_io.cpp
  src/persist.cpp
  src/mailcart.cpp
  src/ffi.cpp)
target_include_directories(tellercore PUBLIC include PRIVATE ${SQLCIPHER_INCLUDE_DIR})
target_compile_definitions(tellercore PRIVATE SQLITE_HAS_CODEC)
target_link_libraries(tellercore
  PUBLIC nlohmann_json::nlohmann_json
  PRIVATE ${SQLCIPHER_LIBRARY} Threads::Threads)
if(TELLERCORE_ENABLE_HTTP)
  target_compile_definitions(tellercore PRIVATE TELLERCORE_ENABLE_HTTP=1)
  target_link_libraries(tellercore PRIVATE httplib::httplib OpenSSL::SSL OpenSSL::Crypto)
endif()
if(TELLERCORE_ENABLE_POSTGRES)
  target_sources(tellercore PRIVATE src/db_postgres.cpp)
  target_include_directories(tellercore PRIVATE ${LIBPQ_INCLUDE_DIR})
  target_compile_definitions(tellercore PRIVATE TELLERCORE_ENABLE_POSTGRES=1)
  target_link_libraries(tellercore PRIVATE ${LIBPQ_LIBRARY})
endif()

get_filename_component(TELLER_SQLITE_DDL
  "${CMAKE_CURRENT_SOURCE_DIR}/../sql/sqlite/create_database.sql" ABSOLUTE)

if(TELLERCORE_BUILD_TOOLS)
  add_executable(teller_oracle_runner tools/oracle_runner.cpp)
  target_link_libraries(teller_oracle_runner PRIVATE tellercore)
  target_include_directories(teller_oracle_runner PRIVATE ${SQLCIPHER_INCLUDE_DIR})
  target_compile_definitions(teller_oracle_runner PRIVATE
    TELLER_SQLITE_DDL_PATH="${TELLER_SQLITE_DDL}")
  if(TELLERCORE_ENABLE_POSTGRES)
    target_compile_definitions(teller_oracle_runner PRIVATE TELLERCORE_ENABLE_POSTGRES=1)
  endif()

  if(TELLERCORE_ENABLE_HTTP)
    add_executable(teller_fetch tools/teller_fetch.cpp)
    target_link_libraries(teller_fetch PRIVATE tellercore httplib::httplib OpenSSL::SSL OpenSSL::Crypto)
    target_include_directories(teller_fetch PRIVATE ${SQLCIPHER_INCLUDE_DIR})
    target_compile_definitions(teller_fetch PRIVATE
      TELLER_SQLITE_DDL_PATH="${TELLER_SQLITE_DDL}" TELLERCORE_ENABLE_HTTP=1)
  endif()
endif()

if(TELLERCORE_BUILD_TESTS)
  FetchContent_Declare(catch2
    URL https://github.com/catchorg/Catch2/archive/refs/tags/v3.7.1.tar.gz
    DOWNLOAD_EXTRACT_TIMESTAMP ON)
  FetchContent_MakeAvailable(catch2)
  enable_testing()
  add_executable(tellercore_tests
    tests/fixture.cpp
    tests/test_profile.cpp
    tests/test_db.cpp
    tests/test_money.cpp
    tests/test_persist.cpp
    tests/test_mailcart.cpp)
  target_include_directories(tellercore_tests PRIVATE ${SQLCIPHER_INCLUDE_DIR})
  target_compile_definitions(tellercore_tests PRIVATE
    TELLER_SQLITE_DDL_PATH="${TELLER_SQLITE_DDL}")
  if(TELLERCORE_ENABLE_POSTGRES)
    # TELLERCORE_TEST_PG_CONNINFO gates the live-Postgres fixture/tests at runtime.
    target_compile_definitions(tellercore_tests PRIVATE TELLERCORE_ENABLE_POSTGRES=1)
  endif()
  target_link_libraries(tellercore_tests PRIVATE tellercore Catch2::Catch2WithMain ${SQLCIPHER_LIBRARY})
  add_test(NAME tellercore_tests COMMAND tellercore_tests)
endif()
