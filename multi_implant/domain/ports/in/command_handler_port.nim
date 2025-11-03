#[
    Port IN: CommandHandlerPort
    Interface for handling incoming commands (driven by infrastructure)
]#

import ../../models/command

type
    CommandHandlerPort* = concept
        ## Port for handling command execution requests
        proc executeCommand*(self, cmd: Command): CommandResult

