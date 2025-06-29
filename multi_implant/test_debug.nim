import json, base64
import util/crypto
import util/strenc

# Test exactly what the multi_implant is sending
echo "=== Debugging Multi-Implant Crypto ==="

# Simulate the exact data structure being sent
var data = %*
    [
        {
            "i": "192.168.0.9",
            "u": "testuser",
            "h": "testhost", 
            "o": "macOS 14.3.0",
            "p": 12345,
            "P": "nimhawk_darwin",
            "r": false
        }
    ]

let dataStr = ($data)[1..^2]
echo "JSON String: ", dataStr
echo "JSON Length: ", dataStr.len

# Test with a fixed key first
let testKey = "FTFLA123456789AB"  # 16 bytes
echo "Test Key: ", testKey

# Test encryption
let encrypted = encryptData(dataStr, testKey)
echo "Encrypted Data Length: ", encrypted.len
echo "Encrypted (first 32 chars): ", encrypted[0..31]

# Test if we can decrypt our own data
let decrypted = decryptData(encrypted, testKey)
echo "Round-trip test success: ", decrypted == dataStr
echo "Decrypted: ", decrypted

# Test with obfuscated strings to see if that's the issue
let obfTestStr = obf("test")
echo "obf() test: '", obfTestStr, "'" 