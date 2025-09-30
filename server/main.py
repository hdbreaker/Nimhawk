import os
import sys
from src.start_servers.start import start_servers

# Add Nim and Zig to PATH for implant compilation
nimble_bin = os.path.expanduser("~/.nimble/bin")
zig_bin = "/tmp/zig-linux-x86_64-0.13.0"
if os.path.exists(nimble_bin) and nimble_bin not in os.environ.get("PATH", ""):
    os.environ["PATH"] = f"{nimble_bin}:{zig_bin}:{os.environ.get('PATH', '')}"


def get_xor_key(force_new=False):
    """Get the XOR key for pre-crypto operations."""
    if os.path.isfile("../.xorkey") and not force_new:
        file = open("../.xorkey", "r", encoding="utf-8")
        xor_key = int(file.read())
    else:
        print(
            "NOTE: No .xorkey file found, run server using python ../nimhawk.py server to initialize it"
        )

    return xor_key

xor_key = get_xor_key()
try:
    name = sys.argv[1]
    print(f"DEBUG: Starting server with provided name: {name}")
    start_servers(xor_key, name)
except IndexError:
    print("DEBUG: No name provided, using default 'Nimhawk'")
    start_servers(xor_key, "Nimhawk")


