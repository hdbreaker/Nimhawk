#!/usr/bin/env python3

import base64

# Server XOR function (Python) - the correct one
def server_xor_string(value, key):
    """Server XOR function from crypto.py"""
    k = key
    result = []
    for c in value:
        character = ord(c)
        for f in [0, 8, 16, 24]:
            character = character ^ (k >> f) & 0xFF
        result.append(character)
        k = k + 1
    return bytes(result)

# Simulation of Nim's XOR function (problematic)
def nimplant_xor_string_simulation(s, key):
    """Simulation of Nim's xorString function"""
    k = key
    result = list(s.encode('latin1') if isinstance(s, str) else s)
    for i in range(len(result)):
        for f in [0, 8, 16, 24]:
            result[i] = result[i] ^ ((k >> f) & 0xFF)
        k = k + 1
    return bytes(result).decode('latin1', errors='replace')

def test_xor_compatibility():
    print("🔧 Testing XOR Compatibility Between Server and Nim Implant")
    print("=" * 60)
    
    # Test data
    INITIAL_XOR_KEY = 459457925
    test_strings = [
        "eIHQ6EQNjpx5wFO2",  # Example from our previous test
        "ABCDEFGHIJ123456",  # 16 chars ASCII
        "TestKey12345678",   # Another 16 chars
        "Hello World!!!!"    # 16 chars with special chars
    ]
    
    for test_str in test_strings:
        print(f"\n🧪 Testing string: '{test_str}' (len: {len(test_str)})")
        
        # Server XOR (correct)
        server_result = server_xor_string(test_str, INITIAL_XOR_KEY)
        server_b64 = base64.b64encode(server_result).decode()
        
        print(f"  📤 Server XOR result (hex): {server_result.hex()}")
        print(f"  📤 Server base64: {server_b64}")
        
        # Simulate what Nim implant receives
        received_bytes = base64.b64decode(server_b64)
        print(f"  📥 Implant receives (hex): {received_bytes.hex()}")
        
        # Try to decode as string (this is where the problem happens)
        try:
            # This is what Nim's base64.decode() returns - a string
            received_str = received_bytes.decode('utf-8')
            print(f"  ✅ UTF-8 decode: SUCCESS")
            print(f"  📥 Received string: '{received_str}'")
            
            # Now apply XOR to get back original
            nim_result = nimplant_xor_string_simulation(received_str, INITIAL_XOR_KEY)
            print(f"  🔄 Nim XOR result: '{nim_result}'")
            print(f"  ✅ Match: {'YES' if nim_result == test_str else 'NO'}")
            
        except UnicodeDecodeError as e:
            print(f"  ❌ UTF-8 decode: FAILED - {e}")
            print(f"  🔧 Problem byte: 0x{received_bytes[e.start]:02x} at position {e.start}")
            
            # Try latin1 decode (what the debug showed works)
            try:
                received_str_latin1 = received_bytes.decode('latin1')
                print(f"  🔄 Latin1 decode: SUCCESS")
                nim_result = nimplant_xor_string_simulation(received_str_latin1, INITIAL_XOR_KEY)
                print(f"  🔄 Nim XOR result: '{nim_result}'")
                print(f"  ✅ Match: {'YES' if nim_result == test_str else 'NO'}")
            except Exception as e2:
                print(f"  ❌ Latin1 decode also failed: {e2}")

if __name__ == "__main__":
    test_xor_compatibility() 