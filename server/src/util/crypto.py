import base64
import random
import string
from Crypto.Cipher import AES
from Crypto.Util import Counter


# XOR function to transmit key securely. Matches nimplant XOR function in 'client/util/crypto.nim'
def xor_string(value, key):
    k = key
    result = []
    for c in value:
        character = ord(c)
        for f in [0, 8, 16, 24]:
            character = character ^ (k >> f) & 0xFF
        result.append(character)
        k = k + 1
    # Return a bytes-like object constructed from the iterator to prevent chr()/encode() issues
    return bytes(result)


# XOR function for working with bytes directly
def xor_bytes(value: bytes, key: int) -> bytes:
    k = key
    result = []
    for byte_val in value:
        # byte_val is already an int when iterating over bytes
        character = byte_val
        for f in [0, 8, 16, 24]:
            character = character ^ (k >> f) & 0xFF
        result.append(character)
        k = k + 1
    return bytes(result)


def random_string(
    size, chars=string.ascii_letters + string.digits + string.punctuation
):
    return "".join(random.choice(chars) for _ in range(size))


# https://stackoverflow.com/questions/3154998/pycrypto-problem-using-aesctr
def encrypt_data(plaintext: str, key: str) -> str:
    iv = random_string(16).encode("UTF-8")
    ctr = Counter.new(128, initial_value=int.from_bytes(iv, byteorder="big"))
    aes = AES.new(key.encode("UTF-8"), AES.MODE_CTR, counter=ctr)
    try:
        ciphertext = iv + aes.encrypt(plaintext.encode("UTF-8"))
    except AttributeError:
        ciphertext = iv + aes.encrypt(plaintext)
    enc = base64.b64encode(ciphertext).decode("UTF-8")
    return enc


def debug_decrypt_data(blob: bytes, key: str) -> str:
    """
    Debug version of decrypt_data with extensive logging
    """
    print(f"🔍 DEBUG: Starting decryption debug")
    print(f"🔍 DEBUG: Input blob type: {type(blob)}")
    print(f"🔍 DEBUG: Input blob length: {len(blob) if blob else 'None'}")
    print(f"🔍 DEBUG: Input key: {key[:5]}...")
    
    try:
        # Step 1: Base64 decode
        ciphertext = base64.b64decode(blob)
        print(f"🔍 DEBUG: Base64 decoded successfully, length: {len(ciphertext)}")
        print(f"🔍 DEBUG: First 32 bytes (hex): {ciphertext[:32].hex()}")
        
        # Step 2: Extract IV
        if len(ciphertext) < 16:
            raise ValueError(f"Ciphertext too short: {len(ciphertext)} bytes, need at least 16")
        
        iv = ciphertext[:16]
        encrypted_payload = ciphertext[16:]
        print(f"🔍 DEBUG: IV (hex): {iv.hex()}")
        print(f"🔍 DEBUG: IV (int): {int.from_bytes(iv, byteorder='big')}")
        print(f"🔍 DEBUG: Encrypted payload length: {len(encrypted_payload)}")
        
        # Step 3: Setup AES-CTR
        ctr = Counter.new(128, initial_value=int.from_bytes(iv, byteorder="big"))
        key_bytes = key.encode("UTF-8")
        print(f"🔍 DEBUG: Key bytes length: {len(key_bytes)}")
        print(f"🔍 DEBUG: Key bytes (hex): {key_bytes.hex()}")
        
        aes = AES.new(key_bytes, AES.MODE_CTR, counter=ctr)
        print(f"🔍 DEBUG: AES-CTR initialized successfully")
        
        # Step 4: Decrypt
        decrypted_bytes = aes.decrypt(encrypted_payload)
        print(f"🔍 DEBUG: Decryption successful, length: {len(decrypted_bytes)}")
        print(f"🔍 DEBUG: First 32 decrypted bytes (hex): {decrypted_bytes[:32].hex()}")
        print(f"🔍 DEBUG: First 32 decrypted bytes (raw): {decrypted_bytes[:32]}")
        
        # Step 5: Attempt UTF-8 decode
        try:
            decoded_text = decrypted_bytes.decode("UTF-8")
            print(f"🔍 DEBUG: UTF-8 decode successful")
            print(f"🔍 DEBUG: Decoded text preview: {decoded_text[:100]}...")
            return decoded_text
        except UnicodeDecodeError as e:
            print(f"🔍 DEBUG: UTF-8 decode failed: {e}")
            print(f"🔍 DEBUG: Problematic byte at position {e.start}: 0x{decrypted_bytes[e.start]:02x}")
            
            # Try other encodings
            for encoding in ['latin1', 'cp1252', 'ascii']:
                try:
                    decoded_text = decrypted_bytes.decode(encoding)
                    print(f"🔍 DEBUG: Successfully decoded with {encoding}")
                    return decoded_text
                except:
                    continue
            
            # Return as escaped string if all else fails
            return decrypted_bytes.decode('utf-8', errors='replace')
            
    except Exception as e:
        print(f"🔍 DEBUG: Exception during decryption: {type(e).__name__}: {e}")
        raise


# Original function with fallback to debug
def decrypt_data(blob: bytes, key: str) -> str:
    try:
        ciphertext = base64.b64decode(blob)
        iv = ciphertext[:16]
        ctr = Counter.new(128, initial_value=int.from_bytes(iv, byteorder="big"))
        aes = AES.new(key.encode("UTF-8"), AES.MODE_CTR, counter=ctr)
        dec = aes.decrypt(ciphertext[16:]).decode("UTF-8")
        return dec
    except UnicodeDecodeError:
        # Fallback to debug version on UTF-8 errors
        print("⚠️  UTF-8 decode failed, switching to debug mode...")
        return debug_decrypt_data(blob, key)


def decrypt_data_to_bytes(blob: bytes, key: str) -> bytes:
    ciphertext = base64.b64decode(blob)
    iv = ciphertext[:16]
    ctr = Counter.new(128, initial_value=int.from_bytes(iv, byteorder="big"))
    aes = AES.new(key.encode("UTF-8"), AES.MODE_CTR, counter=ctr)
    dec = aes.decrypt(ciphertext[16:])
    return dec
