#[
    Domain Model: NetworkCommandContext
    Minimal context for network commands to avoid coupling with full Implant model
    Follows Interface Segregation Principle - modules only depend on what they need
]#

import strutils

type
    NetworkCommandContext* = object
        ## Minimal context for network commands
        ## Contains only the fields needed by network modules
        userAgent*: string
        id*: string
        httpAllowCommunicationKey*: string
        uniqueXorKey*: string
        listenerType*: string
        listenerHost*: string
        implantCallbackIp*: string
        listenerPort*: string
        taskPath*: string

proc newNetworkCommandContext*(
    userAgent: string,
    id: string,
    httpAllowCommunicationKey: string,
    uniqueXorKey: string,
    listenerType: string,
    listenerHost: string,
    implantCallbackIp: string,
    listenerPort: string,
    taskPath: string
): NetworkCommandContext =
    ## Create a new NetworkCommandContext
    result = NetworkCommandContext(
        userAgent: userAgent,
        id: id,
        httpAllowCommunicationKey: httpAllowCommunicationKey,
        uniqueXorKey: uniqueXorKey,
        listenerType: listenerType,
        listenerHost: listenerHost,
        implantCallbackIp: implantCallbackIp,
        listenerPort: listenerPort,
        taskPath: taskPath
    )

proc buildBaseUrl*(ctx: NetworkCommandContext): string =
    ## Build base URL for C2 communication
    ## Returns: "http://host:port" or "http://hostname"
    var baseUrl = ctx.listenerType.toLowerAscii() & "://"
    if ctx.listenerHost != "":
        baseUrl = baseUrl & ctx.listenerHost
    else:
        baseUrl = baseUrl & ctx.implantCallbackIp & ":" & ctx.listenerPort
    return baseUrl

proc buildUploadUrl*(ctx: NetworkCommandContext): string =
    ## Build upload URL for file transfers
    return ctx.buildBaseUrl() & ctx.taskPath & "/u"

proc buildDownloadUrl*(ctx: NetworkCommandContext): string =
    ## Build download URL for file transfers
    return ctx.buildBaseUrl() & ctx.taskPath & "/d"

