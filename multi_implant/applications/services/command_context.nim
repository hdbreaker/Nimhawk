#[
    Command Context
    Minimal interface for commands that need HTTP configuration
    Removes dependency on core/Listener
]#

type
    CommandContext* = object
        ## Minimal context for commands that need HTTP configuration
        id*: string
        uniqueXorKey*: string
        implantCallbackIp*: string
        listenerPort*: string

proc newCommandContext*(id: string = "", uniqueXorKey: string = "", 
                       implantCallbackIp: string = "", listenerPort: string = ""): CommandContext =
    ## Create a new CommandContext
    result = CommandContext(
        id: id,
        uniqueXorKey: uniqueXorKey,
        implantCallbackIp: implantCallbackIp,
        listenerPort: listenerPort
    )

