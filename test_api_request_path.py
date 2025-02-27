#!/usr/bin/env python3
from api import API

def test_request_path():
    # Create API instance with a base URL
    api = API(
        base_url="https://api.example.com/v1/",
        auth_tuple=("user", "pass"),
        cert_pk_tuple=("cert.pem", "key.pem")
    )
    
    # Test cases to verify request_path method
    test_cases = [
        # Standard relative paths - should work fine
        {"path": "resources", "expected": "https://api.example.com/v1/resources"},
        {"path": "/resources", "expected": "https://api.example.com/v1/resources"},
        {"path": "resources/123", "expected": "https://api.example.com/v1/resources/123"},
        
        # Path with query parameter or fragment - should work
        {"path": "resources?filter=active", "expected": "https://api.example.com/v1/resources?filter=active"},
        {"path": "resources#section", "expected": "https://api.example.com/v1/resources#section"},
        
        # Parent directory reference - should work
        {"path": "../resources", "expected": "https://api.example.com/resources"},
        
        # More complex path manipulations
        {"path": "../../resources", "expected": "https://api.example.com/resources"},
        {"path": "/v1/resources", "expected": "https://api.example.com/v1/resources"},
        {"path": "v1/resources", "expected": "https://api.example.com/v1/v1/resources"},
        {"path": "/resources/with/multiple/segments", "expected": "https://api.example.com/v1/resources/with/multiple/segments"},
        {"path": "resources/./with/../cleaned/path", "expected": "https://api.example.com/v1/resources/cleaned/path"},
        {"path": "/resources?query=value&another=value#fragment", "expected": "https://api.example.com/v1/resources?query=value&another=value#fragment"},
        
        # Edge cases with multiple slashes and dots
        {"path": "//resources", "expected": "https://api.example.com/v1/resources"},
        {"path": "resources//nested", "expected": "https://api.example.com/v1/resources/nested"},
        {"path": "./resources", "expected": "https://api.example.com/v1/resources"},
    ]
    
    # Test cases that should raise ValueError (with different domain)
    error_cases = [
        # Different domain (used to silently work with urljoin, now should fail)
        {"path": "https://other.example.com/resources"},
        
        # Different domain with path
        {"path": "https://malicious.com/attack/path"},
        
        # Different domain with same path structure
        {"path": "https://evil.com/v1/resources"},
        
        # Different scheme
        {"path": "http://api.example.com/v1/resources"},
        
        # Path with credentials in URL
        {"path": "https://attacker:password@example.com/resources"},
    ]
    
    # Run tests for valid cases
    print("Testing valid cases:")
    for i, case in enumerate(test_cases):
        try:
            result = api.request_path(case["path"])
            expected = case["expected"]
            if result == expected:
                print(f"✅ Test {i+1} passed: {case['path']} -> {result}")
            else:
                print(f"❌ Test {i+1} failed: {case['path']} -> {result} (expected {expected})")
        except ValueError as e:
            print(f"❌ Test {i+1} failed with exception: {e}")
    
    # Run tests for error cases
    print("\nTesting error cases (should raise ValueError):")
    for i, case in enumerate(error_cases):
        try:
            result = api.request_path(case["path"])
            print(f"❌ Error test {i+1} failed: {case['path']} -> {result} (expected ValueError)")
        except ValueError as e:
            print(f"✅ Error test {i+1} passed with expected exception: {e}")
    
    # Test with a different base URL (no version in path)
    print("\nTesting with base URL without version:")
    simple_api = API(
        base_url="https://simple.example.com/",
        auth_tuple=("user", "pass"),
        cert_pk_tuple=("cert.pem", "key.pem")
    )
    
    simple_cases = [
        {"path": "resources", "expected": "https://simple.example.com/resources"},
        {"path": "/resources", "expected": "https://simple.example.com/resources"},
        {"path": "/v1/resources", "expected": "https://simple.example.com/v1/resources"},
    ]
    
    for i, case in enumerate(simple_cases):
        try:
            result = simple_api.request_path(case["path"])
            expected = case["expected"]
            if result == expected:
                print(f"✅ Simple test {i+1} passed: {case['path']} -> {result}")
            else:
                print(f"❌ Simple test {i+1} failed: {case['path']} -> {result} (expected {expected})")
        except ValueError as e:
            print(f"❌ Simple test {i+1} failed with exception: {e}")

if __name__ == "__main__":
    test_request_path() 