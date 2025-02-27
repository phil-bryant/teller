# RFC-Compliant URL Handling in API Class

This document explains the RFC-compliant URL handling implemented in the `API` class's `request_path` method.

## Overview

The `request_path` method in the `API` class now uses a more secure, RFC-compliant approach for URL merging by leveraging the enhanced `merge_urls` function from the `url_merge` module, which follows RFC 3986 more strictly.

## Key Security Benefits

1. **Domain Protection**: The function rejects any attempt to join URLs with different domains, protecting against potential domain-based attacks.

2. **Path Preservation**: The base URL's path (including version information) is properly preserved when handling absolute paths.

3. **Normalized Path Handling**: Double slashes and other path anomalies are normalized, preventing path traversal issues.

4. **Explicit Error Handling**: Clear error messages are provided when a URL cannot be safely merged, rather than silently allowing potentially dangerous operations.

## Behavioral Differences

| Scenario | Old Behavior (urljoin) | New Behavior (merge_urls) |
|----------|------------------------|----------------------------|
| Different domain | Replaced base URL entirely | Raises ValueError |
| Different scheme | Replaced base URL entirely | Raises ValueError |
| URLs with credentials | Accepted credentials | Raises ValueError |
| Absolute paths | Preserved domain, replaced path | Preserves domain and version prefix |
| Relative paths | Correctly merged | Correctly merged |
| Double slashes | Interpreted inconsistently | Normalized |

## Implementation Details

The `merge_urls` function handles all the complexities of URL merging:

1. Normalizes paths by removing double slashes that aren't part of a protocol
2. Parses URLs to determine if they have a domain
3. For URLs with domains, verifies they can be merged with the base URL
4. For absolute paths, preserves the version component from the base URL
5. For relative paths, ensures the base URL has a trailing slash before merging
6. Raises appropriate `ValueError` exceptions for incompatible URLs with clear error messages

The `request_path` method is now a simple pass-through that calls `merge_urls` directly.

## Example Usage

```python
api = API(base_url="https://api.example.com/v1/", auth_tuple=("user", "pass"), cert_pk_tuple=("cert.pem", "key.pem"))

# Valid paths
api.request_path("resources")  # https://api.example.com/v1/resources
api.request_path("/resources")  # https://api.example.com/v1/resources

# Secure error handling
try:
    api.request_path("https://other.example.com/resources")
except ValueError as e:
    print(f"Caught security issue: {e}")
```

## Why This Matters

This implementation prevents several common security issues:

1. **Server-Side Request Forgery (SSRF)**: By rejecting different domains, it prevents attackers from making the API request internal services.

2. **Open Redirects**: It prevents attackers from crafting URLs that could redirect users to malicious sites.

3. **Unintended API Access**: It ensures that all requests stay within the intended API domain and path structure.

4. **Information Leakage**: By raising errors instead of silently accepting dangerous URLs, it makes unexpected behavior visible.

## Testing

The implementation has been thoroughly tested with a comprehensive test suite that verifies:

- Standard relative and absolute paths
- Paths with query parameters and fragments
- Complex path manipulations and normalizations
- Error handling for various security-sensitive scenarios

The test suite can be found in `test_api_request_path.py`.

## Code Organization

The URL merging functionality has been properly encapsulated in the `url_merge.py` module, making it reusable across different parts of the application and keeping the API class focused on its primary responsibilities.

All URL processing logic, including error handling, has been moved into the `merge_urls` function, making the API class much simpler and more focused. 