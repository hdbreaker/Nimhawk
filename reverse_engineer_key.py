#!/usr/bin/env python3

import base64

def nim_xor_string_exact(s: str, key: int) -> str:
    """Exact simulation of Nim's xorString function"""
    k = key
    result = list(s)
    for i in range(len(result)):
        for f in [0, 8, 16, 24]:
            result[i] = chr(ord(result[i]) ^ ((k >> f) & 0xFF))
        k = k + 1
    return ''.join(result)

def reverse_engineer_from_debug():
    """Work backwards from actual debug data"""
    
    print("🔍 Reverse Engineering from Real Debug Data")
    print("=" * 55)
    
    # REAL data from debug output
    received_b64 = "QkY7S0NKX0VGR1czb19bMg=="
    server_key_hex = "525735444f47554e4e4e5a346b5a5931"
    INITIAL_XOR_KEY = 459457925
    
    # Step 1: What the implant receives
    received_bytes = base64.b64decode(received_b64)
    print(f"📥 Implant received (base64): {received_b64}")
    print(f"📥 Implant received (hex): {received_bytes.hex()}")
    print(f"📥 Implant received (length): {len(received_bytes)}")
    print()
    
    # Step 2: What the server key should be
    server_key_bytes = bytes.fromhex(server_key_hex)
    server_key_str = server_key_bytes.decode('ascii')
    print(f"🏠 Server key (hex): {server_key_hex}")
    print(f"🏠 Server key (string): '{server_key_str}'")
    print(f"🏠 Server key (length): {len(server_key_str)}")
    print()
    
    # Step 3: Test implant XOR decoding
    received_str = received_bytes.decode('latin1')  # Safe conversion
    decoded_key = nim_xor_string_exact(received_str, INITIAL_XOR_KEY)
    
    print(f"🔄 Implant XOR input: '{received_str}' (latin1 decoded)")
    print(f"🔄 Implant XOR result: '{decoded_key}'")
    print(f"🔄 Expected result: '{server_key_str}'")
    print(f"✅ Keys match: {decoded_key == server_key_str}")
    print()
    
    # Step 4: Character-by-character comparison
    print("🔍 Character-by-character analysis:")
    print("Pos | Received | XOR Result | Expected | Match")
    print("----|----------|------------|----------|------")
    
    for i in range(min(len(decoded_key), len(server_key_str))):
        recv_char = received_str[i] if i < len(received_str) else '?'
        dec_char = decoded_key[i] if i < len(decoded_key) else '?'
        exp_char = server_key_str[i] if i < len(server_key_str) else '?'
        match = "✅" if dec_char == exp_char else "❌"
        
        print(f"{i:2d}  | {recv_char:8s} | {dec_char:10s} | {exp_char:8s} | {match}")
    
    print()
    
    # Step 5: If keys don't match, find what SHOULD be received
    if decoded_key != server_key_str:
        print("🛠️  CORRECTING: What should be received for correct key:")
        
        # Reverse the process: XOR the server key to see what should be sent
        correct_xored_str = nim_xor_string_exact(server_key_str, INITIAL_XOR_KEY)
        correct_xored_bytes = correct_xored_str.encode('latin1')
        correct_b64 = base64.b64encode(correct_xored_bytes).decode()
        
        print(f"🔧 Correct XOR result: '{correct_xored_str}'")
        print(f"🔧 Correct bytes (hex): {correct_xored_bytes.hex()}")
        print(f"🔧 Correct base64: {correct_b64}")
        print()
        print(f"🔧 Server sent: {received_b64}")
        print(f"🔧 Should send: {correct_b64}")
        print(f"🔧 Problem: {'Server XOR function' if received_b64 != correct_b64 else 'Implant XOR function'}")

if __name__ == "__main__":
    reverse_engineer_from_debug() 