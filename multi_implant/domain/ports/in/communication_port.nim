#[
    Port IN: CommunicationPort
    Interface for handling communication operations (driven by infrastructure)
]#

import ../../models/[command, implant]

type
    CommunicationPort* = concept
        ## Port for handling communication with C2 server
        proc registerImplant*(self, implant: Implant): bool
        proc reconnectImplant*(self, implant: Implant): bool
        proc pollForCommands*(self, implant: Implant): Command
        proc sendCommandResult*(self, implant: Implant, result: CommandResult): bool

