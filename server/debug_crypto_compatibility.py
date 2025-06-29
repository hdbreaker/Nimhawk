#!/usr/bin/env python3
"""
Nimhawk Crypto Compatibility Debug Tool
Tests encryption/decryption between server Python and implant Nim implementations
"""

import base64
import json
from Crypto.Cipher import AES
from Crypto.Util import Counter
import random
import string

def random_string(length=16):
    """Generate random string for IV/keys"""
    return ''.join(random.choice(string.ascii_letters + string.digits) for _ in range(length))

def xor_string_simple(value: str, key: int) -> str:
    """Simple XOR encryption (like in test scripts)"""
    encrypted = ''.join(chr(ord(c) ^ key) for c in value)
    return base64.b64encode(encrypted.encode()).decode()

def xor_string_complex(s: str, key: int) -> bytes:
    """Complex XOR matching Nim implementation"""
    k = key
    result = []
    for c in s:
        character = ord(c)
        for f in [0, 8, 16, 24]:
            character = character ^ (k >> f) & 0xFF
        result.append(character)
        k = k + 1
    return bytes(result)

def aes_ctr_encrypt(plaintext: str, key: str) -> str:
    """AES-CTR encryption (server implementation)"""
    iv = random_string(16).encode("UTF-8")
    ctr = Counter.new(128, initial_value=int.from_bytes(iv, byteorder="big"))
    aes = AES.new(key.encode("UTF-8"), AES.MODE_CTR, counter=ctr)
    ciphertext = iv + aes.encrypt(plaintext.encode("UTF-8"))
    return base64.b64encode(ciphertext).decode("UTF-8")

def aes_ctr_decrypt(blob: str, key: str) -> str:
    """AES-CTR decryption (server implementation)"""
    ciphertext = base64.b64decode(blob)
    iv = ciphertext[:16]
    ctr = Counter.new(128, initial_value=int.from_bytes(iv, byteorder="big"))
    aes = AES.new(key.encode("UTF-8"), AES.MODE_CTR, counter=ctr)
    dec = aes.decrypt(ciphertext[16:])
    return dec.decode("UTF-8")

def test_crypto_compatibility():
    """Test different encryption scenarios"""
    print("🔧 Nimhawk Crypto Compatibility Test")
    print("=" * 50)
    
    # Test data
    test_data = {"guid": "12345", "result": "SGVsbG8gV29ybGQ="}  # Hello World in base64
    test_json = json.dumps(test_data)
    test_key = "MySecretKey123"
    xor_key = 459457925
    
    print(f"📝 Test Data: {test_json}")
    print(f"🔑 AES Key: {test_key}")
    print(f"🔑 XOR Key: {xor_key}")
    print()
    
    # Test 1: AES-CTR (expected by server)
    print("🧪 Test 1: AES-CTR Encryption/Decryption")
    try:
        encrypted_aes = aes_ctr_encrypt(test_json, test_key)
        print(f"✅ AES-CTR Encrypted: {encrypted_aes[:50]}...")
        
        decrypted_aes = aes_ctr_decrypt(encrypted_aes, test_key)
        print(f"✅ AES-CTR Decrypted: {decrypted_aes}")
        
        if decrypted_aes == test_json:
            print("✅ AES-CTR: PASS")
        else:
            print("❌ AES-CTR: FAIL")
    except Exception as e:
        print(f"❌ AES-CTR Error: {e}")
    print()
    
    # Test 2: Simple XOR (like in test scripts) 
    print("🧪 Test 2: Simple XOR Encryption")
    try:
        encrypted_xor_simple = xor_string_simple(test_json, xor_key)
        print(f"✅ XOR Simple Encrypted: {encrypted_xor_simple[:50]}...")
        
        # Try to decrypt with AES-CTR (this should fail)
        try:
            decrypted_mixed = aes_ctr_decrypt(encrypted_xor_simple, test_key)
            print(f"❌ XOR->AES: This shouldn't work: {decrypted_mixed}")
        except Exception as e:
            print(f"✅ XOR->AES: Expected failure: {type(e).__name__}: {e}")
    except Exception as e:
        print(f"❌ XOR Simple Error: {e}")
    print()
    
    # Test 3: Complex XOR (Nim implementation)
    print("🧪 Test 3: Complex XOR (Nim-style)")
    try:
        encrypted_xor_complex = xor_string_complex(test_json, xor_key)
        encoded_complex = base64.b64encode(encrypted_xor_complex).decode()
        print(f"✅ XOR Complex Encrypted: {encoded_complex[:50]}...")
        
        # Try to decrypt with AES-CTR (this should also fail)
        try:
            decrypted_mixed2 = aes_ctr_decrypt(encoded_complex, test_key)
            print(f"❌ XOR Complex->AES: This shouldn't work: {decrypted_mixed2}")
        except Exception as e:
            print(f"✅ XOR Complex->AES: Expected failure: {type(e).__name__}: {e}")
    except Exception as e:
        print(f"❌ XOR Complex Error: {e}")
    print()
    
    # Test 4: Malformed data
    print("🧪 Test 4: Malformed Data Test")
    malformed_data = base64.b64encode(b"This is not AES encrypted data").decode()
    try:
        decrypted_malformed = aes_ctr_decrypt(malformed_data, test_key)
        print(f"❌ Malformed: This shouldn't work: {decrypted_malformed}")
    except Exception as e:
        print(f"✅ Malformed: Expected failure: {type(e).__name__}: {e}")
    print()
    
    print("💡 ANALYSIS:")
    print("=" * 50)
    print("1. If implant sends XOR-encrypted data but server expects AES-CTR:")
    print("   → UnicodeDecodeError (data corruption)")
    print()
    print("2. If implant sends AES-CTR but with wrong key:")
    print("   → UnicodeDecodeError (decryption with wrong key)")
    print()
    print("3. If implant sends malformed base64:")
    print("   → Base64 decode error or data corruption")
    print()
    print("🔍 NEXT STEPS:")
    print("- Check server logs with debug function")
    print("- Verify implant is using UNIQUE_XOR_KEY for AES, not XOR")
    print("- Confirm key exchange during registration")

if __name__ == "__main__":
    test_crypto_compatibility() 