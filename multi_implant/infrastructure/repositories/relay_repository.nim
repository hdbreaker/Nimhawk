#[
    Repository: RelayRepository
    Implements RelayRepositoryPort
    Manages relay data storage (in-memory for now)
]#

import ../../domain/models/relay_connection
import ../../domain/ports/out/relay_repository_port

type
    RelayRepository* = object
        registrations*: seq[RelayRegistration]
        messages*: seq[RelayMessage]
    
proc newRelayRepository*(): RelayRepository =
    ## Create a new RelayRepository instance
    result = RelayRepository(
        registrations: @[],
        messages: @[]
    )

proc saveRelayRegistration*(repo: var RelayRepository, registration: RelayRegistration) =
    ## Save a relay registration
    repo.registrations.add(registration)

proc getAllRelayRegistrations*(repo: RelayRepository): seq[RelayRegistration] =
    ## Get all relay registrations
    result = repo.registrations

proc clearRelayRegistrations*(repo: var RelayRepository) =
    ## Clear all relay registrations
    repo.registrations = @[]

proc saveRelayMessage*(repo: var RelayRepository, message: RelayMessage) =
    ## Save a relay message
    repo.messages.add(message)

proc getAllRelayMessages*(repo: RelayRepository): seq[RelayMessage] =
    ## Get all relay messages
    result = repo.messages

proc clearRelayMessages*(repo: var RelayRepository) =
    ## Clear all relay messages
    repo.messages = @[]

