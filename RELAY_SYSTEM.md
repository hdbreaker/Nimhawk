# Nimhawk Relay Messaging System

## Overview

The Nimhawk Relay Messaging System (SONET) is a modular, secure, and cross-platform solution for chained communication across multiple agents in restricted network environments. It enables agents to communicate through relay chains when direct C2 communication is not possible.

## Architecture

### Core Components

1. **RelayMessage**: Encrypted message structure for all relay communications
2. **RelayAgent**: Agent that can act as both relay and client
3. **RelayConnection**: Network connection management
4. **RelayServer**: Server for accepting downstream connections

### Message Types

- **REGISTER**: Agent introduces itself to the parent relay
- **PULL**: Agent asks for pending commands
- **COMMAND**: Command to be delivered to an agent
- **RESPONSE**: Response to a command
- **FORWARD**: Message being relayed between agents

### Security Features

- **AES-CTR Encryption**: All payloads encrypted using existing SOR-based crypto modules
- **Route-based Routing**: Messages follow predefined routes through relay chain
- **End-to-End Encryption**: Only origin and destination can decrypt payloads
- **Message Validation**: Integrity checks for all messages

## Usage

### Starting a Relay Server

```bash
# Start relay server on port 8080
relay 8080
```

This command:
- Starts a relay server listening on the specified port
- Accepts connections from downstream agents
- Routes messages between connected agents

### Connecting to an Upstream Relay

```bash
# Connect to relay server at 192.168.1.100:8080
connect relay://192.168.1.100:8080
```

This command:
- Connects to the specified relay server
- Registers the agent with the relay
- Begins polling for commands

### Example Relay Chain

```
C2 Server
    ↓
Agent-A (relay 8080)
    ↓
Agent-B (connect relay://Agent-A:8080, relay 8081)
    ↓
Agent-C (connect relay://Agent-B:8081)
```

In this setup:
- Agent-A acts as a relay for Agent-B
- Agent-B acts as both client (to Agent-A) and relay (for Agent-C)
- Agent-C is a client to Agent-B
- Commands from C2 flow through: C2 → Agent-A → Agent-B → Agent-C

## Message Flow

### Registration Flow

1. Agent connects to relay using `connect` command
2. Agent sends REGISTER message with route information
3. Relay stores agent information and route
4. Relay acknowledges registration

### Command Flow

1. C2 sends command to Agent-A
2. Agent-A determines if command is for downstream agent
3. If yes, creates COMMAND message with target route
4. Message is forwarded through relay chain
5. Target agent receives and processes command
6. Response flows back through same route

### Route Format

Routes are arrays of agent IDs representing the path:
```nim
# Route from Agent-C to C2 through relay chain
route = ["AGENT-C", "AGENT-B", "AGENT-A", "C2"]
```

## Implementation Details

### Cross-Platform Compatibility

The relay system is implemented in both:
- `implant/core/relay/` - Windows-only agent
- `multi_implant/core/relay/` - Cross-platform agent

Both implementations share identical APIs and message formats.

### Encryption Integration

```nim
# Uses existing crypto modules
import ../../util/[crypto, strenc]

# Encrypt payload
proc encryptPayload*(data: string, key: string): string =
    result = encryptData(data, key)  # Uses existing AES-CTR

# Decrypt payload
proc decryptPayload*(encryptedData: string, key: string): string =
    result = decryptData(encryptedData, key)  # Uses existing AES-CTR
```

### OneShot Threading Model

The relay system follows Nimhawk's OneShot model:
- All operations are single-threaded
- Non-blocking message polling
- Event-driven message processing

## Configuration

### Network Settings

Relay agents can be configured with:
- Upstream host and port
- Downstream listening port
- Connection timeouts
- Message queue limits

### Security Settings

- Crypto keys for message encryption
- Agent ID generation
- Route validation rules
- Message expiration times

## Monitoring and Debugging

### Verbose Mode

Enable verbose logging to see relay operations:
```bash
# Compile with verbose flag
nim c -d:verbose -d:mingw NimHawk.nim
```

Verbose output includes:
- Connection establishment
- Message routing decisions
- Registration events
- Error conditions

### Connection Statistics

```nim
# Get relay server statistics
let stats = getConnectionStats(relayServer)
echo "Listening: ", stats.listening
echo "Connections: ", stats.connections
```

## Error Handling

The relay system includes robust error handling:

### Connection Errors
- Automatic reconnection attempts
- Dead connection cleanup
- Graceful degradation

### Message Errors
- Invalid message validation
- Encryption/decryption failures
- Route resolution errors

### Network Errors
- Socket timeout handling
- Connection loss detection
- Port binding failures

## Security Considerations

### Threat Model

The relay system protects against:
- **Message Interception**: All payloads encrypted end-to-end
- **Route Manipulation**: Routes validated and authenticated
- **Relay Compromise**: Relays cannot decrypt message payloads
- **Traffic Analysis**: Message timing and size obfuscation

### Best Practices

1. **Use Strong Keys**: Generate unique crypto keys per operation
2. **Limit Route Length**: Minimize relay hops for performance
3. **Monitor Connections**: Regularly check relay health
4. **Rotate Keys**: Periodically update encryption keys
5. **Validate Routes**: Ensure route integrity before forwarding

## Troubleshooting

### Common Issues

#### Connection Refused
```
ERROR: Failed to connect to relay at 192.168.1.100:8080
```
**Solutions**:
- Check if relay server is running
- Verify firewall settings
- Confirm network connectivity

#### Port Already in Use
```
ERROR: Failed to start relay server on port 8080
```
**Solutions**:
- Choose different port
- Stop existing service on port
- Check for zombie processes

#### Message Routing Failures
```
ERROR: Failed to route message to target agent
```
**Solutions**:
- Verify route configuration
- Check agent connectivity
- Validate message format

## API Reference

### RelayMessage Structure

```nim
type RelayMessage* = object
    msgType*: RelayMessageType     # Message type
    fromID*: string                # Origin agent ID
    route*: seq[string]            # Routing path
    id*: string                    # Unique message ID
    payload*: string               # Encrypted payload
    timestamp*: int64              # Message timestamp
```

### Key Functions

```nim
# Create encrypted message
proc createMessage*(msgType: RelayMessageType, fromID: string, 
                   route: seq[string], payload: string, 
                   cryptoKey: string): RelayMessage

# Process incoming message
proc processMessage*(agent: var RelayAgent, 
                    msg: RelayMessage): seq[RelayMessage]

# Send message through connection
proc sendMessage*(conn: var RelayConnection, 
                 msg: RelayMessage): bool

# Start relay server
proc startRelayServer*(port: int): RelayServer

# Connect to relay
proc connectToRelay*(host: string, port: int): RelayConnection
```

## Future Enhancements

### Planned Features

1. **Dynamic Routing**: Automatic route discovery and optimization
2. **Load Balancing**: Multiple relay paths for redundancy
3. **Compression**: Message payload compression for bandwidth efficiency
4. **Authentication**: Enhanced agent authentication mechanisms
5. **Metrics**: Detailed performance and usage metrics

### Integration Points

- **C2 Server**: Direct integration with Nimhawk server
- **Web UI**: Relay management interface
- **Logging**: Centralized relay activity logging
- **Monitoring**: Real-time relay health monitoring

## Contributing

To contribute to the relay system:

1. Maintain compatibility between Windows and cross-platform agents
2. Follow existing crypto module patterns
3. Include comprehensive error handling
4. Add appropriate verbose logging
5. Update documentation for new features

## License

The relay system is part of Nimhawk and follows the same MIT license terms. 