#[
    Infrastructure Entity: ListenerEntity
    Represents the HTTP listener configuration entity in infrastructure layer
    This is the infrastructure representation of the Implant domain model
]#

type
    ListenerEntity* = object
        ## HTTP listener entity for infrastructure layer
        id*: string
        initialized*: bool
        registered*: bool
        listenerType*: string
        listenerHost*: string
        implantCallbackIp*: string
        listenerPort*: string
        registerPath*: string
        reconnectPath*: string
        sleepTime*: int
        sleepJitter*: float
        killDate*: string
        taskPath*: string
        resultPath*: string
        userAgent*: string
        uniqueXorKey*: string          # UNIQUE_XOR_KEY renamed for consistency
        httpAllowCommunicationKey*: string

proc newListenerEntity*(): ListenerEntity =
    ## Create a new empty ListenerEntity
    result = ListenerEntity(
        id: "",
        initialized: false,
        registered: false,
        listenerType: "HTTP",
        listenerHost: "",
        implantCallbackIp: "127.0.0.1",
        listenerPort: "80",
        registerPath: "/register",
        reconnectPath: "/reconnect",
        sleepTime: 10,
        sleepJitter: 0.0,
        killDate: "",
        taskPath: "/task",
        resultPath: "/result",
        userAgent: "Mozilla/5.0 (Windows NT 10.0; Trident/7.0; rv:11.0) like Gecko",
        uniqueXorKey: "",
        httpAllowCommunicationKey: "DefaultKey123"
    )

