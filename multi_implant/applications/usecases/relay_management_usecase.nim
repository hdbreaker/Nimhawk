#[
    Use Case: RelayManagementUseCase
    Orchestrates relay server and client operations
    Applies Single Responsibility Principle
]#

import ../../domain/models/relay_connection
import ../../domain/ports/out/relay_repository_port

type
    RelayManagementUseCase* = object
        relayRepo*: RelayRepositoryPort
    
proc newRelayManagementUseCase*(relayRepo: RelayRepositoryPort): RelayManagementUseCase =
    ## Create a new RelayManagementUseCase instance
    result = RelayManagementUseCase(relayRepo: relayRepo)

proc registerRelayClient*(useCase: RelayManagementUseCase, registration: RelayRegistration) =
    ## Register a relay client
    when defined debug:
        echo "[DEBUG] RelayManagementUseCase: Registering relay client: " & registration.clientId
    
    useCase.relayRepo.saveRelayRegistration(registration)

proc getPendingRegistrations*(useCase: RelayManagementUseCase): seq[RelayRegistration] =
    ## Get all pending relay registrations
    result = useCase.relayRepo.getAllRelayRegistrations()

proc clearRegistrations*(useCase: RelayManagementUseCase) =
    ## Clear all relay registrations
    useCase.relayRepo.clearRelayRegistrations()

