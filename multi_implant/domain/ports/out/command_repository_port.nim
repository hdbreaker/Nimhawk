#[
    Port OUT: CommandRepositoryPort
    Interface for command persistence and retrieval (provided by infrastructure)
]#

import ../../models/command

type
    CommandRepositoryPort* = concept
        ## Port for command storage and retrieval
        proc saveCommand*(self, cmd: Command)
        proc getCommand*(self, guid: string): Command
        proc saveResult*(self, result: CommandResult)
        proc getResult*(self, guid: string): CommandResult
        proc getAllPendingCommands*(self): seq[Command]
        proc getAllPendingResults*(self): seq[CommandResult]

