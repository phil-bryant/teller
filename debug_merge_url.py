#!/usr/bin/env python3
from url_merge import merge_urls

def debug_merge_urls():
    base_url = "https://api.example.com/v1"
    test_paths = [
        "resources",
        "/resources",
        "resources/123",
        "../resources",
        "v1/resources",
        "v1/resources/123"
    ]
    
    print(f"Base URL: {base_url}")
    print("-" * 50)
    
    for path in test_paths:
        result = merge_urls(base_url, path)
        print(f"Path: {path}")
        print(f"Result: {result}")
        print("-" * 50)
    
    # Test with trailing slash in base URL
    base_url_with_slash = "https://api.example.com/v1/"
    print(f"\nBase URL with trailing slash: {base_url_with_slash}")
    print("-" * 50)
    
    for path in test_paths:
        result = merge_urls(base_url_with_slash, path)
        print(f"Path: {path}")
        print(f"Result: {result}")
        print("-" * 50)

if __name__ == "__main__":
    debug_merge_urls() 