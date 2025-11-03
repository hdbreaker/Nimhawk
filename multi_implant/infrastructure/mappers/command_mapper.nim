#[
    Mapper: CommandMapper
    Maps between domain Command and infrastructure representations
]#

import ../../domain/models/command

proc toDomain*(guid: string, command: string, args: seq[string]): Command =
    ## Convert command parameters to domain Command model
    result = newCommand(guid, command, args)

proc toDomain*(guid: string, command: string, args: seq[string], targetClientId: string): Command =
    ## Convert command parameters with target client ID to domain Command model
    result = newCommand(guid, command, args, targetClientId)

proc toResult*(guid: string, result: string, clientId: string = ""): CommandResult =
    ## Convert result parameters to domain CommandResult model
    result = newCommandResult(guid, result, clientId)

