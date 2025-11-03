#[
    Adapter: FilesystemCommandAdapter
    Wraps filesystem modules (cat, cd, cp, ls, mkdir, mv, pwd, rm)
    Implements CommandModulePort to normalize interfaces
    Applies Dependency Inversion Principle
]#

import options
import ../../../domain/models/network_command_context
import ../../modules/filesystem/[cat, cd, cp, ls, mkdir, mv, pwd, rm]
from ../string_obfuscation_adapter import obf

type
    FilesystemCommandAdapter* = object
        ## Adapter for filesystem command modules
        discard

proc newFilesystemCommandAdapter*(): FilesystemCommandAdapter =
    ## Create a new FilesystemCommandAdapter instance
    result = FilesystemCommandAdapter()

proc executeCommand*(adapter: FilesystemCommandAdapter, cmd: string, args: seq[string], cmdGuid: string, ctx: Option[NetworkCommandContext]): string =
    ## Execute a filesystem command
    ## Normalizes different module interfaces to a single interface
    case cmd:
    of obf("cat"):
        result = cat(args)
    of obf("cd"):
        result = cd(args)
    of obf("cp"):
        result = cp(args)
    of obf("ls"):
        result = ls(args)
    of obf("mkdir"):
        result = mkdir(args)
    of obf("mv"):
        result = mv(args)
    of obf("pwd"):
        result = pwd()
    of obf("rm"):
        result = rm(args)
    else:
        result = obf("ERROR: Unknown filesystem command: ") & cmd

