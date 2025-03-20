# Debugging External Libraries in Cursor IDE

This repository contains configuration files and example scripts to help you debug external Python libraries (like the standard library) in Cursor IDE.

## Files Included

1. **`.vscode/launch.json`** - Contains debug configurations that allow stepping into external libraries
2. **`test_urljoin.py`** - A simple test script that uses urllib.parse.urljoin
3. **`debug_urllib_parse.py`** - A comprehensive script with examples of different urllib.parse functions
4. **`find_urllib_parse.py`** - A utility script to locate the urllib.parse module on your system
5. **`DEBUG_INSTRUCTIONS.md`** - Detailed instructions on how to use these files for debugging

## Quick Start

1. Open `debug_urllib_parse.py` in Cursor IDE
2. Set breakpoints at the lines with comments indicating "Set breakpoint on the next line"
3. Open the Run and Debug panel (usually on the left sidebar)
4. Select "Python: debug_urllib_parse.py" from the dropdown
5. Click the green play button or press F5 to start debugging
6. When execution reaches a breakpoint, press F11 (or use the "Step Into" button) to step into the function

## Key Configuration

The key setting that enables stepping into external libraries is:

```json
"justMyCode": false
```

This is included in all the debug configurations in the `.vscode/launch.json` file.

## More Information

For detailed instructions, see the [DEBUG_INSTRUCTIONS.md](DEBUG_INSTRUCTIONS.md) file.

# RFC-Compliant URL Merging

This repository provides an implementation of URL merging that more strictly follows the RFC 3986 specification compared to Python's standard `urllib.parse.urljoin` function.

## The Problem with `urljoin`

Python's `urljoin` function will completely replace a base URL with an absolute URL from a different domain, which contradicts the purpose of URL reference resolution as described in RFC 3986.

```python
from urllib.parse import urljoin

base_url = "https://example.com/path/"
different_domain = "https://other.com/other/path"

result = urljoin(base_url, different_domain)
print(result)  # Outputs: https://other.com/other/path
```

This behavior is problematic because:

1. It ignores the base URL entirely, which contradicts the purpose of having a base URL
2. It makes it difficult to enforce security policies that restrict which domains can be accessed
3. It can lead to unexpected results in web scraping, crawler applications, or API integrations

## The RFC-Compliant Solution

Our `merge_urls` function enforces stricter rules based on RFC 3986:

```python
from url_merge import merge_urls

base_url = "https://example.com/path/"
different_domain = "https://other.com/other/path"

result = merge_urls(base_url, different_domain)
print(result)  # Outputs: None (indicates URLs cannot be merged)
```

## Key Differences

| Scenario | `urljoin` | `merge_urls` |
|----------|-----------|--------------|
| Relative paths | Appends to base URL | Appends to base URL |
| Absolute paths | Uses base domain with new path | Uses base domain with new path |
| Different domain | Replaces base URL completely | Returns `None` (cannot merge) |
| Incompatible paths on same domain | Replaces with second URL | Returns `None` (cannot merge) |
| Parent directories (../path) | Resolves correctly | Resolves correctly |

## When to Use `merge_urls` vs `urljoin`

Use `merge_urls` when:
- You need to enforce domain restrictions
- You want to ensure URLs are merged only when appropriate
- You need to follow RFC 3986 more strictly
- Security is a priority in your application

Use `urljoin` when:
- You specifically want to replace the base URL with absolute URLs
- Compatibility with existing code is more important than RFC compliance
- You're willing to accept the behaviors not strictly aligned with RFC 3986

## Implementation

The `merge_urls` function works by:

1. Validating the base URL as a proper absolute URL
2. Checking compatibility between the base and second URL
3. Applying RFC 3986 path merging only when appropriate
4. Returning `None` when URLs cannot be properly merged

This approach provides stronger guarantees about URL manipulation in security-sensitive applications.

## Testing

The repository includes comprehensive test scripts:
- `url_merge.py` - The core implementation with basic tests
- `compare_url_merging.py` - Direct comparison with `urljoin`
- `complex_test_cases.py` - Edge cases and complex scenarios

## RFC References

The implementation is based on RFC 3986, particularly:
- Section 5.2 "Relative Resolution"
- Section 5.2.3 "Merge Paths"
- Section 5.2.4 "Remove Dot Segments"

# Teller Database Client

## Environment Setup

The application uses environment variables for database connection. Create a `.env` file in your home directory with the following variables:

```
TELLER_POSTGRES_USER=your_username
TELLER_POSTGRES_PASSWORD=your_password
TELLER_POSTGRES_HOST=your_host
TELLER_POSTGRES_PORT=your_port
TELLER_POSTGRES_DB=your_database
```

## Usage

```python
from teller_db_client import TellerDBClient

# Initialize the client
db = TellerDBClient()

# Connect to the database (uses environment variables by default)
db.connect()

# Or provide a custom connection string
db.connect("host=custom_host dbname=custom_db user=custom_user password=custom_password")

# Query tables
tables = db.get_tables()
```

## Security

- Database credentials are stored in environment variables, not in code
- The `.env` file should be added to `.gitignore` to prevent accidental commits
- For production deployments, use a secure secrets management solution 

# MinimalPostgresClient

A lightweight PostgreSQL client wrapper built around the psycopg driver that provides simplified database operations.

## Features

- Singleton pattern implementation for connection reuse
- Simple query execution with parameter support
- Dictionary-based result rows
- Utility methods for primary key detection and upsert operations
- Schema support

## Dependencies

- psycopg (PostgreSQL driver for Python)

## Basic Usage

```python
from minimal_postgres_client import MinimalPostgresClient

# Initialize client (singleton instance)
client = MinimalPostgresClient(schema="public")

# Connect to database
client.connect("postgresql://user:password@localhost:5432/database")

# Execute simple query
results = client.execute("SELECT * FROM users")
for row in results:
    print(row["id"], row["name"])

# Execute with parameters
user_results = client.execute(
    "SELECT * FROM users WHERE age > %(min_age)s", 
    {"min_age": 21}
)

# Insert or update record
data = {"id": 1, "name": "John Doe", "email": "john@example.com"}
client.upsert("users", data)
client.commit()
```

## Tests

The project includes unit tests that verify the functionality of the client using mocks.

To run the tests:

```bash
python test_minimal_postgres_client.py
```

The tests validate:
- Basic query execution
- Parameter handling
- Different result types
- Error handling

## Implementation Notes

- The client uses a singleton pattern to ensure only one database connection is created
- Row factory is used to return dictionary-based results
- Query parameters use the psycopg named parameter style: `%(param_name)s`
- The client handles queries that return no results 