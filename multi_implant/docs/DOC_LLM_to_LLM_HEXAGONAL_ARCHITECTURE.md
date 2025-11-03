# Technical Documentation: Hexagonal Architecture - Nimhawk Multi-Platform Implant

**Version:** 1.5.0  
**Last Updated:** 2 November 2025  
**Audience:** LLMs and developers using Cursor/IDE for continuous development

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Directory Structure](#directory-structure)
3. [Domain Models](#domain-models)
4. [Ports (Interfaces)](#ports-interfaces)
5. [Adapters and Repositories](#adapters-and-repositories)
6. [Use Cases](#use-cases)
7. [Application Services](#application-services)
8. [Data Flows](#data-flows)
9. [Encryption System](#encryption-system)
10. [Relay System](#relay-system)
11. [Build System and Configuration](#build-system-and-configuration)
12. [Code Conventions](#code-conventions)
13. [Testing](#testing)
14. [Extensions and Development](#extensions-and-development)

---

## Architecture Overview

### Hexagonal Architecture (Ports & Adapters)

This project implements **Hexagonal Architecture** also known as **Ports & Adapters**. The architecture separates business logic (domain) from technical details (infrastructure).

```
┌─────────────────────────────────────────────────────────────┐
│                    APPLICATION LAYER                        │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐       │
│  │   Use Cases  │  │   Services  │  │ Orchestrator │       │
│  └──────────────┘  └──────────────┘  └──────────────┘       │
└─────────────────────────────────────────────────────────────┘
                           ↕
┌─────────────────────────────────────────────────────────────┐
│                      DOMAIN LAYER                           │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐      │
│  │    Models    │  │ Ports (IN)   │  │ Ports (OUT)  │      │
│  └──────────────┘  └──────────────┘  └──────────────┘      │
└─────────────────────────────────────────────────────────────┘
                           ↕
┌─────────────────────────────────────────────────────────────┐
│                 INFRASTRUCTURE LAYER                         │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐      │
│  │  Adapters    │  │ Repositories │  │   Modules    │      │
│  └──────────────┘  └──────────────┘  └──────────────┘      │
└─────────────────────────────────────────────────────────────┘
```

### SOLID Principles Applied

- **Single Responsibility Principle (SRP)**: Each module has a single responsibility
- **Open/Closed Principle (OCP)**: Open for extension, closed for modification
- **Liskov Substitution Principle (LSP)**: Adapters are interchangeable via ports
- **Interface Segregation Principle (ISP)**: Specific and focused ports
- **Dependency Inversion Principle (DIP)**: Dependencies point toward domain, not infrastructure

### Implant Roles

The system supports three roles:

1. **STANDARD**: Direct implant that connects to the C2 server
2. **RELAY_CLIENT**: Implant that connects through a relay gateway
3. **RELAY_SERVER**: Implant that acts as a relay server for other clients

---

## Directory Structure

```
multi_implant/
├── main.nim                          # Main entry point
├── config.toml                       # Configuration (copied from ../config.toml on build)
├── Makefile                          # Multi-platform build system
├── multi_implant.nimble              # Nim package descriptor
│
├── domain/                           # DOMAIN LAYER (Business Logic)
│   ├── models/                       # Domain models (entities)
│   │   ├── implant.nim              # Implant model with configuration and state
│   │   ├── command.nim               # Command and CommandResult models
│   │   ├── network_command_context.nim  # Context for network commands
│   │   ├── network_health.nim       # Network health state
│   │   └── relay_connection.nim      # Relay models (HttpRelayConfig, etc.)
│   │
│   └── ports/                        # PORTS (Interfaces)
│       ├── in/                       # Input ports (driven by infrastructure)
│       │   ├── command_handler_port.nim
│       │   ├── communication_port.nim
│       │   └── relay_handler_port.nim
│       │
│       └── out/                      # Output ports (driven by application)
│           ├── command_module_port.nim
│           ├── command_repository_port.nim
│           ├── communication_repository_port.nim
│           ├── relay_repository_port.nim
│           ├── string_obfuscation_port.nim
│           └── system_info_port.nim
│
├── applications/                     # APPLICATION LAYER (Orchestration)
│   ├── services/                     # Application services
│   │   ├── implant_orchestrator_service.nim  # Main lifecycle orchestrator
│   │   └── command_service.nim       # Command execution service
│   │
│   └── usecases/                     # Use cases
│       ├── register_implant_usecase.nim      # C2 registration
│       ├── poll_commands_usecase.nim        # Command polling
│       ├── execute_command_usecase.nim      # Command execution
│       └── relay_management_usecase.nim      # Relay management
│
└── infrastructure/                   # INFRASTRUCTURE LAYER (Technical Details)
    ├── adapters/                     # Adapters (implement ports)
    │   ├── http_client_adapter.nim   # HTTP communication with C2
    │   ├── relay_client_adapter.nim  # HTTP relay client
    │   ├── relay_server_adapter.nim  # HTTP relay server
    │   ├── string_obfuscation_adapter.nim   # String obfuscation
    │   ├── command_module_registry.nim      # Command modules registry
    │   │
    │   └── command_modules/          # Category-specific adapters
    │       ├── filesystem_command_adapter.nim
    │       ├── network_command_adapter.nim
    │       ├── system_command_adapter.nim
    │       ├── execution_command_adapter.nim
    │       ├── screenshot_command_adapter.nim
    │       └── relay_command_adapter.nim
    │
    ├── repositories/                 # Repositories (implement OUT ports)
    │   ├── communication_repository.nim     # C2 communication
    │   ├── command_repository.nim           # Command storage
    │   ├── relay_repository.nim             # Relay management
    │   └── system_info_repository.nim       # System information
    │
    ├── modules/                       # Functional modules (concrete implementations)
    │   ├── execution/
    │   ├── filesystem/
    │   ├── network/
    │   ├── relay/
    │   ├── risky/                    # Risky commands (optional)
    │   ├── screenshot/
    │   └── system/
    │
    ├── mappers/                       # Mappers between layers
    │   ├── implant_mapper.nim        # Converts between Implant and ListenerEntity
    │   └── command_mapper.nim        # Converts between Command and representations
    │
    ├── entities/                      # Infrastructure entities
    │   └── listener_entity.nim      # Internal entity for HTTP adapter
    │
    ├── config/                        # Configuration
    │   ├── config_loader.nim         # Configuration loading
    │   └── config_parser.nim         # TOML parsing
    │
    └── util/                          # Utilities
        ├── crypto.nim                # Encryption/decryption functions
        ├── strenc.nim                # String encoding/obfuscation
        ├── sysinfo.nim               # System information
        └── route_manager.nim          # Route management
```

### Dependency Rules

```
✅ VALID:
- applications/ → domain/
- infrastructure/ → domain/
- applications/ → infrastructure/ (only concrete port implementations)

❌ INVALID:
- domain/ → applications/
- domain/ → infrastructure/
- applications/ → applications/ (except services)
```

---

## Domain Models

### Implant (`domain/models/implant.nim`)

Represents the implant with its configuration and state.

```nim
type
    ImplantRole* = enum
        STANDARD
        RELAY_CLIENT
        RELAY_SERVER
    
    Implant* = object
        # Identity
        id*: string                    # Unique ID assigned by C2
        initialized*: bool            # Whether initialized
        registered*: bool             # Whether registered with C2
        role*: ImplantRole            # Implant role
        
        # C2 Configuration
        listenerType*: string         # Listener type (HTTP, HTTPS)
        listenerHost*: string         # Listener hostname
        implantCallbackIp*: string    # C2 server IP
        listenerPort*: string         # C2 server port
        
        # HTTP Paths
        registerPath*: string         # Registration endpoint
        taskPath*: string             # Polling endpoint
        resultPath*: string           # Results endpoint
        reconnectPath*: string        # Reconnection endpoint
        
        # Communication settings
        userAgent*: string            # User agent string
        httpAllowCommunicationKey*: string  # Authentication key
        uniqueXorKey*: string         # Unique encryption key from C2
        
        # Operational settings
        sleepTime*: int               # Sleep interval in seconds
        sleepJitter*: float           # Jitter percentage
        killDate*: string             # Expiration date
```

**Important methods:**
- `newImplant()`: Creates a new uninitialized implant
- `isExpired()`: Checks if the implant has expired
- `isRelayMode()`: Checks if in relay mode
- `toNetworkContext()`: Converts to NetworkCommandContext for network commands

### Command (`domain/models/command.nim`)

Represents a command and its result.

```nim
type
    Command* = object
        guid*: string              # Unique command identifier
        command*: string           # Command name (e.g., "ls", "whoami")
        args*: seq[string]         # Command arguments
        targetClientId*: string    # Target client ID (for relay routing)
        timestamp*: int64          # Command timestamp
    
    CommandResult* = object
        guid*: string              # GUID matching the command
        result*: string            # Execution result
        clientId*: string          # ID of client that executed the command
        timestamp*: int64          # Result timestamp
```

### NetworkCommandContext (`domain/models/network_command_context.nim`)

Context needed for network commands (allows network modules to depend only on what they need).

```nim
type
    NetworkCommandContext* = object
        userAgent*: string
        id*: string
        httpAllowCommunicationKey*: string
        uniqueXorKey*: string
        listenerType*: string
        listenerHost*: string
        implantCallbackIp*: string
        listenerPort*: string
        taskPath*: string
```

### RelayConnection (`domain/models/relay_connection.nim`)

Relay-related models.

```nim
type
    HttpRelayConfig* = object
        gatewayHost*: string
        gatewayPort*: int
        relayClientId*: string        # Temporary relay connection ID
        cumulusAgentId*: string       # Real C2-assigned agent ID
        isConnected*: bool
        isRegistered*: bool           # Whether registered with C2
```

---

## Ports (Interfaces)

### Input Ports (IN) - Driven by Infrastructure

These ports define interfaces that infrastructure can use to communicate with the application.

#### CommandHandlerPort (`domain/ports/in/command_handler_port.nim`)

```nim
type
    CommandHandlerPort* = concept
        proc executeCommand*(self, cmd: string, args: seq[string]): string
        proc getCommandHistory*(self): seq[Command]
```

#### CommunicationPort (`domain/ports/in/communication_port.nim`)

```nim
type
    CommunicationPort* = concept
        proc registerImplant*(self, implant: Implant): bool
        proc reconnectImplant*(self, implant: Implant): bool
        proc pollForCommands*(self, implant: Implant): Command
        proc sendCommandResult*(self, implant: Implant, result: CommandResult): bool
```

#### RelayHandlerPort (`domain/ports/in/relay_handler_port.nim`)

```nim
type
    RelayHandlerPort* = concept
        proc startRelayServer*(self, port: int): bool
        proc stopRelayServer*(self): bool
        proc connectToRelay*(self, host: string, port: int): bool
        proc disconnectFromRelay*(self): bool
        proc isRelayServerRunning*(self): bool
        proc isRelayClientConnected*(self): bool
```

### Output Ports (OUT) - Driven by Application

These ports define interfaces that the application needs from infrastructure.

#### CommunicationRepositoryPort (`domain/ports/out/communication_repository_port.nim`)

```nim
type
    CommunicationRepositoryPort* = concept
        proc registerWithC2*(self, implant: Implant, localIP: string, 
                           username: string, hostname: string, osInfo: string, 
                           pid: int, processName: string, isRelay: bool, 
                           role: string): Future[bool]
        proc reconnectToC2*(self, implant: Implant): Future[bool]
        proc getQueuedCommand*(self, implant: Implant): Future[tuple[guid: string, command: string, args: seq[string]]]
        proc postCommandResults*(self, implant: Implant, guid: string, result: string): Future[bool]
        proc postRelayRegisterRequest*(self, implant: Implant, clientId: string, 
                                      localIP: string, username: string, hostname: string,
                                      osInfo: string, pid: int, processName: string,
                                      isRelay: bool, role: string): Future[bool]
        proc postChainInfo*(self, implant: Implant, agentId: string, chainInfo: string, 
                           role: string, connections: int): Future[bool]
```

#### CommandModulePort (`domain/ports/out/command_module_port.nim`)

```nim
type
    CommandModulePort* = concept
        proc executeCommand*(self, cmd: string, args: seq[string], 
                           cmdGuid: string, ctx: Option[NetworkCommandContext]): string
```

#### SystemInfoPort (`domain/ports/out/system_info_port.nim`)

```nim
type
    SystemInfoPort* = concept
        proc getCurrentPID*(self): int
        proc getCurrentProcessName*(self): string
        proc getOSInfo*(self): string
        proc getUsername*(self): string
        proc getHostname*(self): string
        proc getLocalIP*(self): string
```

---

## Adapters and Repositories

### HttpClientAdapter (`infrastructure/adapters/http_client_adapter.nim`)

**Responsibility:** Handles all HTTP communication with the C2 server.

**Implements:** `CommunicationRepositoryPort` (implicitly)

**Key functions:**

1. **`registerWithC2()`**: Registers the implant with the C2 server
   - Sends system information (IP, user, hostname, OS, PID, process name)
   - Receives the implant ID and unique encryption key
   - Format: POST to `registerPath` with JSON

2. **`getQueuedCommand()`**: Gets queued commands from C2
   - Performs GET to `taskPath`
   - **Decryption process:**
     ```
     JSON["t"] (base64) 
     → base64.decode() 
     → XOR decrypt with INITIAL_XOR_KEY (envelope layer)
     → base64.encode() (re-encode for decryptData)
     → decryptData() with uniqueXorKey (AES-128-CTR, content layer)
     → JSON parse of result
     ```

3. **`postCommandResults()`**: Sends command results
   - Performs POST to `resultPath`
   - Encrypts result with AES-128-CTR using `uniqueXorKey`

**Important HTTP headers:**
- `X-Request-ID`: Implant ID (after registration)
- `X-Correlation-ID`: Authentication key (`httpAllowCommunicationKey`)
- `X-Robots-Tag`: Workspace UUID (if configured)
- `User-Agent`: Configured user agent string

### RelayClientAdapter (`infrastructure/adapters/relay_client_adapter.nim`)

**Responsibility:** Handles relay client communication with the gateway.

**Key functions:**

1. **`initRelayClient()`**: Initializes the relay client
   - Configures host, port, and temporary agent ID

2. **`testGatewayConnection()`**: Tests connection to gateway
   - GET to `/health` or similar endpoint

3. **`registerCumulusAgentViaGateway()`**: Registers agent with C2 through gateway
   - POST to `/proxy` with `communication_array` JSON
   - Format:
     ```json
     {
       "communication_array": [
         {
           "agent_id": "temporal-id",
           "ip": "gateway-host:port",
           "encrypted_message": "REGISTRATION_REQUEST"
         }
       ]
     }
     ```

4. **`pollGatewayForCommands()`**: Polls gateway for commands
   - POST to `/proxy` with `"encrypted_message": "COMMAND_REQUEST"`
   - Returns `(guid, command, args)`

5. **`sendResultToGateway()`**: Sends results to gateway
   - POST to `/proxy` with result in `encrypted_message`

### CommandModuleRegistry (`infrastructure/adapters/command_module_registry.nim`)

**Responsibility:** Registry that maps commands to their appropriate adapters.

**Pattern:** Strategy Pattern

**Structure:**

```nim
type
    CommandModuleRegistry* = object
        filesystemAdapter*: FilesystemCommandAdapter
        networkAdapter*: NetworkCommandAdapter
        systemAdapter*: SystemAdapter
        executionAdapter*: ExecutionCommandAdapter
        screenshotAdapter*: ScreenshotCommandAdapter
        relayAdapter*: RelayCommandAdapter
        commandMap*: Table[string, string]  # "ls" -> "filesystem"
```

**Mapped commands:**

- **Filesystem:** `cat`, `cd`, `cp`, `ls`, `mkdir`, `mv`, `pwd`, `rm`
- **Network:** `curl`, `download`, `upload`, `wget`
- **System:** `env`, `getav`, `getdom`, `getlocaladm`, `ps`, `whoami`
- **Execution:** `run`
- **Screenshot:** `screenshot`
- **Relay:** `relay`

**Main method:**

```nim
proc executeCommand*(registry: CommandModuleRegistry, cmd: string, 
                    args: seq[string], cmdGuid: string, 
                    ctx: Option[NetworkCommandContext]): string
```

- Searches command in `commandMap`
- Delegates to appropriate adapter
- Network commands require `NetworkCommandContext`

### Repositories

#### CommunicationRepository (`infrastructure/repositories/communication_repository.nim`)

**Implements:** `CommunicationRepositoryPort`

**Delegates to:** `HttpClientAdapter` for actual HTTP operations

**Functions:**
- `registerWithC2()`: Async wrapper of `httpAdapter.registerWithC2()`
- `getQueuedCommand()`: Async wrapper of `httpAdapter.getQueuedCommand()`
- `postCommandResults()`: Async wrapper of `httpAdapter.postCommandResults()`

#### CommandRepository (`infrastructure/repositories/command_repository.nim`)

**Responsibility:** In-memory storage of commands and results.

**Structure:**

```nim
type
    CommandRepository* = object
        commands*: Table[string, Command]      # GUID -> Command
        results*: Table[string, CommandResult]  # GUID -> CommandResult
        commandsQueue*: seq[Command]             # Queue of commands from C2
        resultsQueue*: seq[CommandResult]        # Queue of results for C2
```

#### SystemInfoRepository (`infrastructure/repositories/system_info_repository.nim`)

**Implements:** `SystemInfoPort`

**Delegates to:** `infrastructure/util/sysinfo.nim` for system operations

**Functions:**
- `getCurrentPID()`: Current process PID
- `getCurrentProcessName()`: Current process name
- `getOSInfo()`: OS information
- `getUsername()`: Current user
- `getHostname()`: System hostname
- `getLocalIP()`: Local IP

---

## Use Cases

### RegisterImplantUseCase (`applications/usecases/register_implant_usecase.nim`)

**Responsibility:** Orchestrate implant registration with the C2 server.

**Flow:**

1. Gets system information (`SystemInfoRepository`)
2. Determines implant role (STANDARD/RELAY_CLIENT/RELAY_SERVER)
3. Calls `CommunicationRepository.registerWithC2()`
4. Updates implant with received ID
5. Returns `(success: bool, updatedImplant: Implant)`

**Methods:**
- `register()`: Initial registration
- `reconnect()`: Reconnection after disconnection

### PollCommandsUseCase (`applications/usecases/poll_commands_usecase.nim`)

**Responsibility:** Polling commands from the C2 server.

**Flow:**

1. Calls `CommunicationRepository.getQueuedCommand()`
2. Converts response to `Command` domain model
3. Returns command or empty command if none available

**Methods:**
- `pollForCommand()`: Polling a command
- `sendResult()`: Sending result

### ExecuteCommandUseCase (`applications/usecases/execute_command_usecase.nim`)

**Responsibility:** Execute commands using CommandService.

**Flow:**

1. Receives command and arguments
2. Delegates to `CommandService.executeCommand()`
3. Returns result as string

---

## Application Services

### ImplantOrchestratorService (`applications/services/implant_orchestrator_service.nim`)

**Responsibility:** Orchestrate the complete implant lifecycle.

**Components:**

```nim
type
    ImplantOrchestratorService* = ref object
        implant*: Implant
        commandService*: CommandService
        communicationRepo*: CommunicationRepository
        commandRepo*: CommandRepository
        systemInfoRepo*: SystemInfoRepository
        registerUseCase*: RegisterImplantUseCase
        pollUseCase*: PollCommandsUseCase
        executeUseCase*: ExecuteCommandUseCase
        networkHealth*: NetworkHealth
        isRunning*: bool
```

**Main flow (`runPollingLoop()`):**

```nim
1. initialize()
   ├─ Registers implant with C2 (RegisterImplantUseCase)
   └─ Configures initial state

2. Main loop:
   ├─ Poll for commands (PollCommandsUseCase)
   ├─ If command available:
   │  ├─ Execute command (ExecuteCommandUseCase)
   │  ├─ Store result in CommandRepository
   │  └─ Send result to C2 (PollCommandsUseCase.sendResult)
   ├─ Sleep with jitter
   └─ Check killDate
```

**Main methods:**

- `initialize()`: Initializes and registers the implant
- `runPollingLoop()`: Main polling loop
- `shutdown()`: Graceful shutdown

### CommandService (`applications/services/command_service.nim`)

**Responsibility:** Encapsulates command execution logic.

**Structure:**

```nim
type
    CommandService* = object
        commandModuleRegistry*: CommandModuleRegistry
```

**Main method:**

```nim
proc executeCommand*(service: CommandService, implant: Implant, 
                    cmd: string, cmdGuid: string, args: seq[string]): string
```

**Flow:**

1. Determines if command requires `NetworkCommandContext`
2. If network command, converts `Implant` to `NetworkCommandContext`
3. Delegates to `CommandModuleRegistry.executeCommand()`
4. Returns result

---

## Data Flows

### Registration Flow (STANDARD Mode)

```
main.nim
  └─> runMultiImplant()
      └─> ImplantOrchestratorService.new()
      └─> orchestrator.initialize()
          └─> RegisterImplantUseCase.register()
              ├─> SystemInfoRepository.get*() [gets system info]
              └─> CommunicationRepository.registerWithC2()
                  └─> HttpClientAdapter.registerWithC2()
                      ├─> Builds JSON with system info
                      ├─> POST to /register
                      ├─> Parses JSON response
                      ├─> Extracts ID and uniqueXorKey
                      └─> Returns (success, updatedImplant)
```

### Command Polling Flow (STANDARD Mode)

```
ImplantOrchestratorService.runPollingLoop()
  └─> PollCommandsUseCase.pollForCommand()
      └─> CommunicationRepository.getQueuedCommand()
          └─> HttpClientAdapter.getQueuedCommand()
              ├─> GET to /task with headers (X-Request-ID, etc.)
              ├─> Parses JSON response["t"]
              ├─> base64.decode(response["t"])
              ├─> XOR decrypt with INITIAL_XOR_KEY
              ├─> base64.encode() [re-encode]
              ├─> decryptData() with uniqueXorKey [AES-128-CTR]
              ├─> Parses JSON from decrypted result
              └─> Returns (guid, command, args)
  └─> If command available:
      └─> ExecuteCommandUseCase.execute()
          └─> CommandService.executeCommand()
              └─> CommandModuleRegistry.executeCommand()
                  └─> Specific adapter (e.g., FilesystemCommandAdapter)
                      └─> Functional module (e.g., ls.nim)
  └─> PollCommandsUseCase.sendResult()
      └─> CommunicationRepository.postCommandResults()
          └─> HttpClientAdapter.postCommandResults()
              ├─> encryptData() with uniqueXorKey
              ├─> base64.encode()
              └─> POST to /result
```

### Relay Client Flow

```
main.nim
  └─> runMultiImplant()
      └─> If RELAY_ADDR defined:
          └─> RelayClientAdapter.new()
          └─> relayAdapter.initRelayClient()
          └─> relayAdapter.testGatewayConnection()
          └─> relayAdapter.registerCumulusAgentViaGateway()
              └─> POST to gateway:/proxy with communication_array
          └─> Main loop:
              └─> relayAdapter.pollGatewayForCommands()
                  └─> POST to gateway:/proxy with COMMAND_REQUEST
              └─> CommandService.executeCommand()
              └─> relayAdapter.sendResultToGateway()
                  └─> POST to gateway:/proxy with result
```

---

## Encryption System

### Encryption Layers

The system uses **layered encryption**:

1. **Envelope Layer (XOR)**: XOR encryption with `INITIAL_XOR_KEY` (compile-time)
2. **Content Layer (AES)**: AES-128-CTR encryption with `uniqueXorKey` (from C2)

### Encryption Functions (`infrastructure/util/crypto.nim`)

#### XOR Functions

```nim
proc xorString*(s: string, key: int): string
```
- Applies XOR byte-by-byte using a 32-bit key
- Key rotation: `k = k + 1` after each byte
- Used for envelope layer before key exchange

#### AES Functions

```nim
proc encryptData*(data: string, key: string): string
```
- AES-128 encryption in CTR mode
- Generates random 16-byte IV
- Format: `base64(IV || encrypted_data)`
- Returns base64 string

```nim
proc decryptData*(blob: string, key: string): string
```
- AES-128 decryption in CTR mode
- Expects base64 input
- Extracts IV from first 16 bytes
- Decrypts remaining data
- Returns decrypted string (without null padding)

### Command Decryption Flow

```nim
# In getQueuedCommand():

let encryptedTask = responseJson["t"].getStr()  # Base64 string from JSON
let base64Decoded = base64.decode(encryptedTask)  # Decode base64

# Step 1: XOR decrypt (envelope layer)
let xorDecrypted = xorString(base64Decoded, INITIAL_XOR_KEY)

# Step 2: Re-encode to base64 (decryptData expects base64)
let xorDecryptedBase64 = base64.encode(xorDecrypted)

# Step 3: AES decrypt (content layer)
let decryptedTask = decryptData(xorDecryptedBase64, entity.uniqueXorKey)

# Step 4: Parse JSON
let taskJson = parseJson(decryptedTask)
```

### Result Encryption Flow

```nim
# In postCommandResults():

let encrypted = encryptData(output, entity.uniqueXorKey)  # AES-128-CTR + base64
let postBody = %*{"guid": cmdGuid, "result": encrypted}
POST to /result with JSON body
```

### Important Keys

- **`INITIAL_XOR_KEY`**: Defined at compile-time (`-d:INITIAL_XOR_KEY=...`)
- **`uniqueXorKey`**: Received from C2 during registration, stored in `Implant.uniqueXorKey`

---

## Relay System

### Relay Architecture

The system supports **HTTP relay** where an implant can act as:

1. **Relay Client**: Connects to a relay gateway instead of directly to C2
2. **Relay Server**: Acts as gateway for other clients

### Relay Client

**Compilation configuration:**

```makefile
make darwin_arm64 RELAY_ADDRESS=relay://gateway-host:port DEBUG=1
```

**Compilation variables:**
- `RELAY_ADDRESS`: Gateway URL (`relay://host:port`)
- `FAST_MODE`: Shorter polling intervals (0.5-1s)

**Flow:**

1. **Initialization:**
   ```
   RelayClientAdapter.initRelayClient(host, port, agentId)
   ```

2. **Registration:**
   ```
   POST /proxy
   {
     "communication_array": [
       {
         "agent_id": "temporal-id",
         "ip": "gateway-host:port",
         "encrypted_message": "REGISTRATION_REQUEST"
       }
     ]
   }
   ```
   - Gateway returns the real C2 `cumulusAgentId`

3. **Polling:**
   ```
   POST /proxy
   {
     "communication_array": [
       {
         "agent_id": "cumulus-agent-id",
         "ip": "gateway-host:port",
         "encrypted_message": "COMMAND_REQUEST"
       }
     ]
   }
   ```

4. **Sending Results:**
   ```
   POST /proxy
   {
     "communication_array": [
       {
         "agent_id": "cumulus-agent-id",
         "ip": "gateway-host:port",
         "encrypted_message": "<encrypted_result>"
       }
     ]
   }
   ```

### Relay Server

**Available commands:**

- `relay port 9999`: Starts relay server on port 9999
- `relay status`: Shows relay status
- `relay stop`: Stops relay server

**Implementation:** `infrastructure/modules/relay/proxy_server.nim`

---

## Build System and Configuration

### Makefile

**Location:** `Makefile` in project root

**Main targets:**

- `linux_x64`: Linux x86_64
- `linux_arm64`: Linux ARM64
- `linux_mipsel`: Linux MIPS Little-Endian
- `linux_arm`: Linux ARM
- `darwin_intelx64`: macOS Intel x86_64
- `darwin_arm64`: macOS Apple Silicon ARM64
- `darwin`: Both Darwin architectures
- `all`: All platforms

**Options:**

```makefile
# Debug mode
make darwin_arm64 DEBUG=1

# Verbose mode
make darwin_arm64 VERBOSE=1

# Relay client
make darwin_arm64 RELAY_ADDRESS=relay://192.168.1.100:9999 DEBUG=1

# Fast mode (relay clients)
make darwin_arm64 RELAY_ADDRESS=relay://192.168.1.100:9999 FAST_MODE=1 DEBUG=1

# Custom XOR key
make darwin_arm64 XOR_KEY=123456789 DEBUG=1
```

**Important variables:**

- `XOR_KEY`: Initial XOR key (default: from `../.xorkey` or 459457925)
- `RELAY_ADDRESS`: Relay gateway address
- `RELAY_SERVER_PORT`: Relay server port (hybrid mode)
- `RELAY_ROLE`: Relay role (client/server)

**Automatic configuration:**

The Makefile automatically copies `../config.toml` to `./config.toml` before building (target `config.toml`).

### Configuration (config.toml)

**Location:** `config.toml` (copied from `../config.toml` on build)

**Expected structure:**

```toml
listenerType = "HTTP"
hostname = "example.com"
implantCallbackIp = "192.168.1.100"
listenerPort = "80"
listenerRegPath = "/register"
listenerTaskPath = "/task"
listenerResPath = "/result"
reconnectPath = "/reconnect"
userAgent = "Mozilla/5.0 ..."
httpAllowCommunicationKey = "DefaultKey123"
sleepTime = "10"
sleepJitter = "0"
killDate = "2024-12-31"
workspace_uuid = "optional-uuid"
```

**Loading:** `infrastructure/config/config_loader.nim` → `parseConfig()` → `Table[string, string]`

### Compilation

**Basic command:**

```bash
nim c -d:release -d:puppyLibcurl \
  --os:macosx --cpu:arm64 \
  -d:INITIAL_XOR_KEY=459457925 \
  -o:bin/nimhawk_darwin_arm64 \
  main.nim
```

**Important flags:**

- `-d:release`: Release build
- `-d:debug`: Debug build (with `-d:verbose` for logs)
- `-d:puppyLibcurl`: Uses libcurl for HTTP (multi-platform)
- `-d:INITIAL_XOR_KEY=...`: Initial XOR key
- `-d:RELAY_ADDRESS="relay://..."`: Relay gateway address
- `-d:FAST_MODE`: Fast mode for relay clients

---

## Code Conventions

### Naming Conventions

**Files:**
- `snake_case.nim` for files
- `*_adapter.nim`: Adapters
- `*_repository.nim`: Repositories
- `*_usecase.nim`: Use cases
- `*_service.nim`: Services
- `*_port.nim`: Ports/interfaces

**Types:**
- `PascalCase` for types: `Implant`, `CommandService`
- `*Port` for interfaces: `CommunicationRepositoryPort`
- `*Adapter` for adapters: `HttpClientAdapter`
- `*Repository` for repositories: `CommunicationRepository`

**Procedures:**
- `camelCase` for procedures: `executeCommand`, `registerWithC2`
- `new*()` for constructors: `newImplant()`, `newCommandService()`

**Constants:**
- `SCREAMING_SNAKE_CASE` for constants: `INITIAL_XOR_KEY`

### Imports

**Import order:**

1. Standard Nim imports
2. External package imports
3. Domain imports (models, ports)
4. Application imports (usecases, services)
5. Infrastructure imports (adapters, repositories)

**Example:**

```nim
import asyncdispatch, json, strutils
import puppy
import ../../domain/models/implant
import ../../domain/ports/out/communication_repository_port
import ../usecases/register_implant_usecase
import ../../infrastructure/adapters/http_client_adapter
```

### Documentation

**Comment format:**

```nim
#[
    Application Service: CommandService
    Encapsulates command execution logic
    Applies Single Responsibility Principle
]#
```

**Procedure documentation:**

```nim
proc executeCommand*(service: CommandService, implant: Implant, 
                    cmd: string, cmdGuid: string, args: seq[string]): string =
    ## Execute a command using the appropriate adapter
    ## 
    ## Arguments:
    ##   - service: CommandService instance
    ##   - implant: Implant domain model
    ##   - cmd: Command name
    ##   - cmdGuid: Command GUID
    ##   - args: Command arguments
    ## 
    ## Returns:
    ##   Command execution result as string
```

### Error Handling

**Strategy:**

- Use `Option[T]` when value may not exist
- Use `Result[T, E]` or tuples `(success: bool, value: T)` for operations that may fail
- Use `try/except` for operations that may throw exceptions (HTTP, I/O)

**Example:**

```nim
proc registerWithC2*(...): Future[(bool, Implant)] {.async.} =
    try:
        # ... operation ...
        return (true, updatedImplant)
    except Exception as e:
        when defined debug:
            echo "[ERROR] Registration failed: " & e.msg
        return (false, implant)
```

### Debugging

**Compilation flags:**

- `-d:debug`: Enables debug logs
- `-d:verbose`: Enables detailed logs

**Usage:**

```nim
when defined debug:
    echo "[DEBUG] Registering implant..."

when defined verbose:
    echo obf("DEBUG: Response body: ") & response.body
```

**String obfuscation:**

Use `obf()` to obfuscate strings in logs:

```nim
from infrastructure/adapters/string_obfuscation_adapter import obf

echo obf("DEBUG: Command received")
```

---

## Testing

### Test Structure

```
tests/
├── unit/                          # Unit tests
│   ├── applications/
│   ├── domain/
│   └── infrastructure/
├── integration/                   # Integration tests
│   ├── test_command_execution_flow.nim
│   ├── test_implant_lifecycle.nim
│   └── test_unified_system_integration.nim
└── scenarios/                     # Test scenarios
```

### Running Tests

```bash
# All unit tests
nim c -r tests/unit/test_all_unit.nim

# Integration tests
nim c -r tests/integration/test_all_integration.nim

# All tests
nim c -r tests/run_all_tests.nim
```

### Testing Strategy

1. **Unit Tests**: Each component individually
2. **Integration Tests**: Complete flows (registration → polling → execution → result)
3. **Scenario Tests**: Specific use cases

---

## Extensions and Development

### Adding a New Command

**Steps:**

1. **Implement functional module** in `infrastructure/modules/<category>/`

```nim
# infrastructure/modules/filesystem/newcmd.nim
proc executeNewCmd*(args: seq[string]): string =
    ## Execute newcmd command
    # ... implementation ...
```

2. **Add adapter** in `infrastructure/adapters/command_modules/`

```nim
# infrastructure/adapters/command_modules/filesystem_command_adapter.nim
proc executeNewCmd*(adapter: FilesystemCommandAdapter, args: seq[string]): string =
    include ../../modules/filesystem/newcmd
    return executeNewCmd(args)
```

3. **Register in CommandModuleRegistry**

```nim
# infrastructure/adapters/command_module_registry.nim
registry.commandMap[obf("newcmd")] = "filesystem"
```

4. **Update adapter** to handle the command

```nim
case cmd:
of obf("newcmd"):
    return adapter.executeNewCmd(args)
```

### Adding a New Command Category

**Steps:**

1. Create specific adapter: `infrastructure/adapters/command_modules/<category>_command_adapter.nim`
2. Add to `CommandModuleRegistry`
3. Implement functional modules in `infrastructure/modules/<category>/`

### Adding a New Port

**Steps:**

1. Define port in `domain/ports/in/` or `domain/ports/out/`
2. Implement adapter that implements the port
3. Use the port in use cases or services

### Modifying Encryption Flow

**Location:** `infrastructure/util/crypto.nim` and `infrastructure/adapters/http_client_adapter.nim`

**Considerations:**

- Maintain compatibility with existing C2 server
- Current format is: `base64(IV || AES-128-CTR(data))`
- Envelope layer XOR is applied before key exchange

### Modifying HTTP Communication

**Location:** `infrastructure/adapters/http_client_adapter.nim`

**Key functions:**

- `doRequest()`: Generic HTTP request function
- `registerWithC2()`: Registration
- `getQueuedCommand()`: Polling
- `postCommandResults()`: Sending results

**Custom headers:**

Add in `doRequest()` where headers are constructed.

---

## Critical Development Points

### 1. Layer Dependencies

✅ **ALWAYS VALID:**
- `applications/` → `domain/`
- `infrastructure/` → `domain/`
- `applications/` → `infrastructure/` (only concrete implementations)

❌ **NEVER VALID:**
- `domain/` → `applications/`
- `domain/` → `infrastructure/`
- `infrastructure/` → `applications/` (except for specific services)

### 2. Port Usage

Ports define **contracts**. Adapters **implement** these contracts.

- **OUT Ports**: Application needs them → infrastructure implements them
- **IN Ports**: Infrastructure needs them → application implements them

### 3. Mappers

Mappers (`infrastructure/mappers/`) convert between:
- Domain models (`Implant`) ↔ Infrastructure entities (`ListenerEntity`)

**Reason:** Keep domain clean of infrastructure details.

### 4. Async/Await

- Network operations are **async**
- Repositories return `Future[T]`
- Use cases use `{.async.}` and `await`

### 5. Configuration

- Configuration is loaded from `config.toml`
- Parsed to `Table[string, string]`
- Accessed with `getOrDefault(key, default)`

### 6. Error Handling in Communication

- Always use `try/except` in HTTP operations
- Return tuples `(success: bool, ...)` or `Option[T]`
- Log errors with `when defined debug`

### 7. String Obfuscation

- Use `obf()` for sensitive strings in logs
- Commands are obfuscated in `CommandModuleRegistry`

---

## Quick References

### Entry Point

- **File:** `main.nim`
- **Main function:** `runMultiImplant()`
- **Paths:**
  - STANDARD: `ImplantOrchestratorService`
  - RELAY_CLIENT: `RelayClientAdapter` direct loop

### Key Components

| Component | Location | Responsibility |
|-----------|----------|----------------|
| `ImplantOrchestratorService` | `applications/services/` | Implant lifecycle |
| `CommandService` | `applications/services/` | Command execution |
| `HttpClientAdapter` | `infrastructure/adapters/` | HTTP communication with C2 |
| `CommandModuleRegistry` | `infrastructure/adapters/` | Command routing |
| `CommunicationRepository` | `infrastructure/repositories/` | Async HTTP wrapper |

### Main Flows

1. **Registration:** `main.nim` → `ImplantOrchestratorService.initialize()` → `RegisterImplantUseCase.register()` → `HttpClientAdapter.registerWithC2()`
2. **Polling:** `ImplantOrchestratorService.runPollingLoop()` → `PollCommandsUseCase.pollForCommand()` → `HttpClientAdapter.getQueuedCommand()`
3. **Execution:** `CommandService.executeCommand()` → `CommandModuleRegistry.executeCommand()` → Specific adapter → Functional module

---

## Conclusion

This document provides a comprehensive view of the hexagonal architecture of the Nimhawk Multi-Platform Implant project. For continuous development:

1. **Respect layers**: Do not violate dependencies between layers
2. **Use ports**: Define interfaces before implementing
3. **Keep domain clean**: Do not include infrastructure details in domain
4. **Follow conventions**: Use naming conventions and consistent structure
5. **Document changes**: Update this document when adding new components

**Last updated:** This document reflects the code state after fixing the decryption flow in `getQueuedCommand()` where base64 re-encoding was added after XOR decrypt.

---

**Document maintained by:** LLM development system  
**Contact:** See repository for issues and contributions
