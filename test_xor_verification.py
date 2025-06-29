#!/usr/bin/env python3

import base64

def server_xor_string(value: str, key: int) -> bytes:
    """Exact server XOR function"""
    k = key
    result = []
    for c in value:
        character = ord(c)
        for f in [0, 8, 16, 24]:
            character = character ^ (k >> f) & 0xFF
        result.append(character)
        k = k + 1
    return bytes(result)

def nim_xor_string_original(s: str, key: int) -> str:
    """Original Nim xorString function simulation"""
    k = key
    result = list(s)
    for i in range(len(result)):
        for f in [0, 8, 16, 24]:
            result[i] = chr(ord(result[i]) ^ ((k >> f) & 0xFF))
        k = k + 1
    return ''.join(result)

def nim_xor_bytes_new(data: bytes, key: int) -> str:
    """New Nim xorBytes function simulation"""
    k = key
    result = []
    for i in range(len(data)):
        byte_val = data[i]
        for f in [0, 8, 16, 24]:
            byte_val = byte_val ^ ((k >> f) & 0xFF)
        result.append(chr(byte_val))
        k = k + 1
    return ''.join(result)

def test_real_scenario():
    """Test the exact scenario from the debug output"""
    
    # From debug: server generated encryption_key starts with "RW5DO"
    # Let's assume it's "RW5DOGUNNNZ4kZY1" (16 chars to match hex length)
    encryption_key = "RW5DOGUNNNZ4kZY1"
    INITIAL_XOR_KEY = 459457925
    
    print("🔧 Testing Real Scenario from Debug")
    print("=" * 50)
    print(f"Original encryption_key: '{encryption_key}'")
    print(f"INITIAL_XOR_KEY: {INITIAL_XOR_KEY}")
    print()
    
    # Step 1: Server XORs the key for transmission
    server_xored = server_xor_string(encryption_key, INITIAL_XOR_KEY)
    server_b64 = base64.b64encode(server_xored).decode()
    
    print(f"🏠 Server XOR result (hex): {server_xored.hex()}")
    print(f"🏠 Server base64: {server_b64}")
    print()
    
    # Expected from debug: QkY7S0NKX0VGR1czb19bMg==
    debug_b64 = "QkY7S0NKX0VGR1czb19bMg=="
    debug_bytes = base64.b64decode(debug_b64)
    
    print(f"🔍 Debug base64: {debug_b64}")
    print(f"🔍 Debug bytes (hex): {debug_bytes.hex()}")
    print(f"🔍 Match server XOR: {server_xored.hex() == debug_bytes.hex()}")
    print()
    
    # Step 2: Test both XOR methods
    print("🧪 Testing XOR decoding methods:")
    
    # Method 1: Original xorString (string input)
    decoded_str = debug_bytes.decode('latin1')  # Convert bytes to string safely
    result1 = nim_xor_string_original(decoded_str, INITIAL_XOR_KEY)
    print(f"  🔄 Original xorString: '{result1}'")
    print(f"  ✅ Match: {result1 == encryption_key}")
    
    # Method 2: New xorBytes (bytes input)
    result2 = nim_xor_bytes_new(debug_bytes, INITIAL_XOR_KEY)
    print(f"  🔄 New xorBytes: '{result2}'")
    print(f"  ✅ Match: {result2 == encryption_key}")
    
    print()
    
    # Step 3: Find the correct encryption key by reverse engineering
    print("🔍 Reverse engineering from debug data:")
    
    # We know the server key bytes should be: 525735444f47554e4e4e5a346b5a5931
    expected_hex = "525735444f47554e4e4e5a346b5a5931"
    expected_key = bytes.fromhex(expected_hex).decode('ascii')
    
    print(f"  📊 Expected key from server hex: '{expected_key}'")
    
    # Test if this key produces the same XOR result
    test_xored = server_xor_string(expected_key, INITIAL_XOR_KEY)
    test_b64 = base64.b64encode(test_xored).decode()
    
    print(f"  🧪 Test XOR result: {test_b64}")
    print(f"  ✅ Match debug: {test_b64 == debug_b64}")

if __name__ == "__main__":
    test_real_scenario() 