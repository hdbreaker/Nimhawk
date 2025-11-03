#[
    Domain Model: Command
    Represents a command to be executed by the implant
]#

import times

type
    Command* = object
        guid*: string              # Unique identifier for the command
        command*: string           # Command name (e.g., "ls", "whoami")
        args*: seq[string]         # Command arguments
        targetClientId*: string    # Target client ID (for relay routing)
        timestamp*: int64          # Command timestamp
    
    CommandResult* = object
        guid*: string              # Unique identifier matching the command
        result*: string            # Command execution result
        clientId*: string          # Client ID that executed the command
        timestamp*: int64          # Result timestamp

proc newCommand*(guid: string, command: string, args: seq[string] = @[], targetClientId: string = "", timestamp: int64 = 0): Command =
    ## Create a new Command instance
    result = Command(
        guid: guid,
        command: command,
        args: args,
        targetClientId: targetClientId,
        timestamp: if timestamp == 0: epochTime().int64 else: timestamp
    )

proc newCommandResult*(guid: string, resultStr: string, clientId: string = "", timestamp: int64 = 0): CommandResult =
    ## Create a new CommandResult instance
    result = CommandResult(
        guid: guid,
        result: resultStr,
        clientId: clientId,
        timestamp: if timestamp == 0: epochTime().int64 else: timestamp
    )

