import times, tables, random
import relay_protocol

# Global topology tracking - moved here to avoid circular dependencies
var g_localTopology*: TopologyInfo
var g_topologyInitialized*: bool = false

# Global relay client ID - moved here to avoid circular dependencies  
var g_relayClientID*: string = ""

# Global relay server ID - moved here to avoid circular dependencies
var g_relayServerID*: string = ""

# Generate fixed relay server ID
proc getRelayServerID*(): string =
    if g_relayServerID == "":
        # Generate ONCE and reuse forever
        randomize()
        let randomPart = rand(1000..9999)
        g_relayServerID = "RELAY-SERVER-" & $randomPart
        when defined debug:
            echo "[DEBUG] 🆔 Generated FIXED relay server ID: " & g_relayServerID
    return g_relayServerID

# Set relay client ID
proc setRelayClientID*(clientID: string) =
    g_relayClientID = clientID

# Get relay client ID
proc getRelayClientID*(): string =
    return g_relayClientID 