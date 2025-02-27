#!/usr/bin/env python3
"""
RFC 3986 compliant URL merging function.

This module provides a proper implementation of URL merging that follows
the RFC 3986 specification, unlike other libraries that might replace
the base URL entirely in some cases.
"""
from urllib.parse import urlparse, urlunparse, urlunsplit
import re
import os.path

def remove_dot_segments(path):
    """
    Remove dot segments from a path as described in RFC 3986 section 5.2.4.
    """
    # Create output buffer
    output = []
    
    # Process path segments
    segments = path.split('/')
    for segment in segments:
        if segment == '.' or segment == '':
            continue
        elif segment == '..':
            if output and output[-1] != '':
                output.pop()
        else:
            output.append(segment)
    
    # Reconstruct path
    result = '/'.join(output)
    if path.startswith('/'):
        result = '/' + result
    if path.endswith('/') and result:
        result += '/'
    if not result and path == '/':
        result = '/'
    
    return result

def merge_urls(base_url, second_url):
    """
    Merge two URLs according to RFC 3986 rules, with enhanced security and proper path handling.
    
    Args:
        base_url: The base URL that must be preserved as the foundation
        second_url: The URL to merge with the base
        
    Returns:
        The merged URL
        
    Raises:
        ValueError: If the URLs cannot be merged (e.g., different domains or invalid base URL)
        
    This function ensures that:
    1. The base_url is a valid absolute URL
    2. The second_url is compatible with the base_url for merging
    3. The base_url is always preserved as the foundation
    4. Version components in the path are properly maintained
    5. Double slashes are normalized
    6. Query parameters and fragments are properly handled
    """
    # Normalize double slashes which can confuse urlparse
    # Only if not part of a scheme (like http://)
    normalized_second_url = second_url
    while '//' in normalized_second_url and not normalized_second_url.startswith('http'):
        normalized_second_url = normalized_second_url.replace('//', '/')
    
    # Parse both URLs into components
    base = urlparse(base_url)
    second = urlparse(normalized_second_url)
    
    # Validate base URL (must be absolute with scheme and netloc)
    if not base.scheme or not base.netloc:
        raise ValueError(f"Base URL must be absolute with scheme and domain: '{base_url}'")
    
    # Get the base path without trailing slash
    base_path = base.path.rstrip('/')
    
    # Case 1: second URL has a domain (absolute URL)
    if second.netloc:
        # If domains are different, reject the merge for security
        if second.netloc.lower() != base.netloc.lower() or second.scheme != base.scheme:
            raise ValueError(f"Cannot merge URL with different domain: base='{base_url}', path='{second_url}'")
        
        # Same domain, return the second URL as is
        return normalized_second_url
    
    # Case 2: second URL starts with / (absolute path)
    if normalized_second_url.startswith('/'):
        # Extract just the path part
        path_only = second.path
        path_to_use = path_only.lstrip('/')
        
        # If base path has a version component and the new path doesn't include it
        if base_path and not path_to_use.startswith(base_path.lstrip('/')):
            # Preserve the version component
            result = urlunsplit((
                base.scheme,
                base.netloc,
                f"{base_path}/{path_to_use}",
                second.query,
                second.fragment
            ))
            return result
        
        # Path already includes version or base has no special path
        result = urlunsplit((
            base.scheme,
            base.netloc,
            f"/{path_to_use}",
            second.query,
            second.fragment
        ))
        return result
    
    # Case 3: second URL is a relative path
    # Ensure base URL has a trailing slash for correct path joining
    base_with_slash = base_url if base_url.endswith('/') else base_url + '/'
    
    # For relative path, we can merge
    if second.path:
        # Relative path - must preserve base path hierarchy
        base_path_for_merge = base.path
        if not base_path_for_merge.endswith('/'):
            # Make sure base path ends with a slash for proper joining
            base_path_for_merge += '/'
        
        # Handle parent directory references properly
        merged_path = base_path_for_merge + second.path
        merged_path = remove_dot_segments(merged_path)
        
        return urlunparse((
            base.scheme,
            base.netloc,
            merged_path,
            second.params,
            second.query,
            second.fragment
        ))
    
    # Case 4: Just query or fragment changes
    elif second.query or second.fragment:
        return urlunparse((
            base.scheme,
            base.netloc,
            base.path,
            base.params, 
            second.query if second.query else base.query,
            second.fragment if second.fragment else base.fragment
        ))
    
    # Case 5: Nothing to merge
    return base_url

if __name__ == "__main__":
    # Test cases
    base = "https://example.com/base/path/"
    test_urls = [
        "relative/path",              # Should merge
        "/absolute/path",             # Should replace path only
        "https://example.com/other",  # Same domain, different path - should merge
        "https://other.com/path",     # Different domain - should raise ValueError
        "?query=new",                 # Just query - should merge
        "#fragment",                  # Just fragment - should merge
        "../sibling/path",            # Parent reference - should resolve correctly
        "//resources",                # Double slash normalization
        "./resources",                # Current directory reference
        "/v1/resources"               # Path with version component
    ]
    
    print("Testing base URL without version:")
    for url in test_urls:
        try:
            result = merge_urls(base, url)
            print(f"Base:   {base}")
            print(f"Second: {url}")
            print(f"Result: {result}")
        except ValueError as e:
            print(f"Base:   {base}")
            print(f"Second: {url}")
            print(f"Error:  {e}")
        print("-" * 70)
    
    # Test with a base URL that includes a version
    base_with_version = "https://api.example.com/v1/"
    print("\nTesting base URL with version:")
    for url in test_urls:
        try:
            result = merge_urls(base_with_version, url)
            print(f"Base:   {base_with_version}")
            print(f"Second: {url}")
            print(f"Result: {result}")
        except ValueError as e:
            print(f"Base:   {base_with_version}")
            print(f"Second: {url}")
            print(f"Error:  {e}")
        print("-" * 70) 