#[
    Port OUT: RelayRepositoryPort
    Interface for relay data persistence (provided by infrastructure)
]#

import ../../models/relay_connection

type
    RelayRepositoryPort* = concept
        ## Port for relay data storage and retrieval
        proc saveRelayRegistration*(self, registration: RelayRegistration)
        proc getAllRelayRegistrations*(self): seq[RelayRegistration]
        proc clearRelayRegistrations*(self)
        proc saveRelayMessage*(self, message: RelayMessage)
        proc getAllRelayMessages*(self): seq[RelayMessage]
        proc clearRelayMessages*(self)

