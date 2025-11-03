#[
    Port IN: RelayHandlerPort
    Interface for handling relay operations (driven by infrastructure)
]#

import ../../models/relay_connection

type
    RelayHandlerPort* = concept
        ## Port for handling relay operations
        proc startRelayServer*(self, port: int): bool
        proc stopRelayServer*(self): bool
        proc connectToRelay*(self, host: string, port: int): bool
        proc disconnectFromRelay*(self): bool
        proc isRelayServerRunning*(self): bool
        proc isRelayClientConnected*(self): bool

