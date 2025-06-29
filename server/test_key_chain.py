#!/usr/bin/env python3
"""
Test Key Chain Compatibility
Simulates the exact key generation and usage flow between server and implant
"""

import base64
import json
import random
import string
from Crypto.Cipher import AES
from Crypto.Util import Counter
from secrets import choice

def xor_string_server(value: str, key: int) -> bytes:
    """Server XOR function - EXACT copy from server/src/util/crypto.py"""
    k = key
    result = []
    for c in value:
        character = ord(c)
        for f in [0, 8, 16, 24]:
            character = character ^ (k >> f) & 0xFF
        result.append(character)
        k = k + 1
    return bytes(result)

def xor_string_implant(s: str, key: int) -> str:
    """Implant XOR function - EXACT copy from implant logic"""
    k = key
    result = s
    result_list = list(result)
    for i in range(len(result_list)):
        for f in [0, 8, 16, 24]:
            result_list[i] = chr(ord(result_list[i]) ^ ((k >> f) & 0xFF))
        k = k + 1
    return ''.join(result_list)

def server_encrypt_aes_ctr(plaintext: str, key: str) -> str:
    """Server AES-CTR encryption"""
    # Fixed IV for testing
    iv = b"1234567890123456"  # 16 bytes
    ctr = Counter.new(128, initial_value=int.from_bytes(iv, byteorder="big"))
    aes = AES.new(key.encode("UTF-8"), AES.MODE_CTR, counter=ctr)
    ciphertext = iv + aes.encrypt(plaintext.encode("UTF-8"))
    return base64.b64encode(ciphertext).decode("UTF-8")

def server_decrypt_aes_ctr(blob: str, key: str) -> str:
    """Server AES-CTR decryption"""
    ciphertext = base64.b64decode(blob)
    iv = ciphertext[:16]
    ctr = Counter.new(128, initial_value=int.from_bytes(iv, byteorder="big"))
    aes = AES.new(key.encode("UTF-8"), AES.MODE_CTR, counter=ctr)
    dec = aes.decrypt(ciphertext[16:])
    return dec.decode("UTF-8")

def test_key_compatibility():
    """Test the complete key generation and usage chain"""
    print("🔧 Testing Nimhawk Key Chain Compatibility")
    print("=" * 60)
    
    # Step 1: Server generates encryption_key (EXACTLY like NimPlant class)
    encryption_key = "".join(choice(string.ascii_letters + string.digits) for x in range(16))
    initial_xor_key = 459457925  # Default INITIAL_XOR_KEY
    
    print(f"1️⃣  Server generated encryption_key: '{encryption_key}'")
    print(f"1️⃣  INITIAL_XOR_KEY: {initial_xor_key}")
    print()
    
    # Step 2: Server XORs encryption_key with INITIAL_XOR_KEY (for transmission)
    xored_bytes = xor_string_server(encryption_key, initial_xor_key)
    encoded_key = base64.b64encode(xored_bytes).decode("utf-8")
    
    print(f"2️⃣  Server XOR'd key (bytes): {xored_bytes.hex()}")
    print(f"2️⃣  Server encoded key (base64): {encoded_key}")
    print()
    
    # Step 3: Implant receives and decodes the key
    received_bytes = base64.b64decode(encoded_key)
    received_string = received_bytes.decode('latin1')  # Convert bytes to string
    unique_xor_key = xor_string_implant(received_string, initial_xor_key)
    
    print(f"3️⃣  Implant received bytes: {received_bytes.hex()}")
    print(f"3️⃣  Implant decoded UNIQUE_XOR_KEY: '{unique_xor_key}'")
    print(f"3️⃣  Keys match: {unique_xor_key == encryption_key}")
    print()
    
    if unique_xor_key != encryption_key:
        print("❌ KEY MISMATCH - This is the problem!")
        print(f"   Original:  '{encryption_key}' (len: {len(encryption_key)})")
        print(f"   Recovered: '{unique_xor_key}' (len: {len(unique_xor_key)})")
        print()
        
        # Debug the difference
        for i, (a, b) in enumerate(zip(encryption_key, unique_xor_key)):
            if a != b:
                print(f"   Diff at pos {i}: '{a}' (0x{ord(a):02x}) vs '{b}' (0x{ord(b):02x})")
        return False
    
    # Step 4: Test AES-CTR encryption/decryption with both keys
    test_data = {"guid": "12345", "result": "SGVsbG8gV29ybGQ="}
    test_json = json.dumps(test_data)
    
    print(f"4️⃣  Test data: {test_json}")
    
    # Implant encrypts with UNIQUE_XOR_KEY
    encrypted_by_implant = server_encrypt_aes_ctr(test_json, unique_xor_key)
    print(f"4️⃣  Encrypted by implant: {encrypted_by_implant[:50]}...")
    
    # Server decrypts with original encryption_key
    try:
        decrypted_by_server = server_decrypt_aes_ctr(encrypted_by_implant, encryption_key)
        print(f"4️⃣  Decrypted by server: {decrypted_by_server}")
        
        if decrypted_by_server == test_json:
            print("✅ AES-CTR encryption/decryption: SUCCESS")
            return True
        else:
            print("❌ AES-CTR data mismatch")
            return False
            
    except UnicodeDecodeError as e:
        print(f"❌ AES-CTR Unicode error: {e}")
        print("   This is the exact error you're seeing!")
        return False
    except Exception as e:
        print(f"❌ AES-CTR error: {type(e).__name__}: {e}")
        return False

def test_byte_conversion_issue():
    """Test potential byte conversion issues"""
    print("\n🔍 Testing Byte Conversion Issues")
    print("=" * 40)
    
    # Test problematic characters
    test_keys = [
        "ABCDEFGHIJ123456",  # Safe ASCII
        "ABCDéFGHIJ12345",   # Extended ASCII
        "ABC\x80\x90\xa0DEF123",  # High bytes
    ]
    
    initial_xor_key = 459457925
    
    for i, key in enumerate(test_keys):
        print(f"\nTest {i+1}: '{key}' (len: {len(key)})")
        
        try:
            # Server side
            xored_bytes = xor_string_server(key, initial_xor_key)
            encoded = base64.b64encode(xored_bytes).decode("utf-8")
            
            # Implant side - this is where it might fail
            received_bytes = base64.b64decode(encoded)
            
            # Try different decodings
            for encoding in ['latin1', 'utf-8', 'cp1252']:
                try:
                    received_string = received_bytes.decode(encoding)
                    recovered_key = xor_string_implant(received_string, initial_xor_key)
                    
                    print(f"  {encoding:8}: '{recovered_key}' - {'✅' if recovered_key == key else '❌'}")
                    
                except UnicodeDecodeError as e:
                    print(f"  {encoding:8}: UnicodeDecodeError: {e}")
                    
        except Exception as e:
            print(f"  ERROR: {e}")

if __name__ == "__main__":
    print("Starting comprehensive key compatibility test...\n")
    
    success = test_key_compatibility()
    test_byte_conversion_issue()
    
    print("\n" + "=" * 60)
    if success:
        print("🎉 KEY CHAIN TEST: PASSED")
        print("   The key generation and AES encryption should work correctly.")
        print("   If you're still seeing UTF-8 errors, the problem is elsewhere.")
    else:
        print("💥 KEY CHAIN TEST: FAILED")
        print("   This is likely the root cause of your UTF-8 errors.")
        print("   The keys don't match between server and implant.")
    
    print("\n🔍 NEXT STEPS:")
    print("1. Run this test to verify key compatibility")
    print("2. If keys don't match, fix the XOR implementation")
    print("3. If keys match, the problem is in the actual implant code")
    print("4. Use the debug_decrypt_data function to analyze real traffic") 