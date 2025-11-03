#[
    Port OUT: CommandModulePort
    Interface for command module execution (provided by infrastructure)
    Defines the contract for command modules that execute specific commands
]#

import ../models/network_command_context

type
    CommandModulePort* = concept
        ## Port for command module execution
        ## Any type that implements this concept can execute commands
        proc executeCommand*(self, cmd: string, args: seq[string], cmdGuid: string, ctx: Option[NetworkCommandContext]): string
            ## Execute a command with given arguments
            ## cmd: The command name
            ## args: Command arguments
            ## cmdGuid: Command GUID for tracking
            ## ctx: Optional network context (only needed for network commands)
            ## Returns the command output as a string


