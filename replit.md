# Nimhawk C2 Framework

## Overview

Nimhawk is a command and control (C2) framework designed for educational and authorized red teaming. It comprises a Python backend server, a React/Next.js frontend for operator interaction, Nim-based implants for target systems, and an SQLite database for data storage. The framework utilizes a client-server architecture with HTTP/HTTPS for communication, enabling operators to manage implants via a web interface.

## User Preferences

Preferred communication style: Simple, everyday language.

## System Architecture

### Backend Architecture

The backend is built with Python 3.8+ and Flask, using Gevent for asynchronous handling and SQLite (via APSW) for data persistence. Communication is secured with XOR and AES-CTR encryption. It includes an Admin API for the web UI and operator commands, and an Implants Server for implant callbacks. A single `nimhawk.db` file simplifies data management, and configuration is handled via `config.toml`.

### Frontend Architecture

The frontend uses Next.js 15.x with React 18, Mantine UI v7, and SWR for data fetching. It follows a static site generation approach, uses a centralized API layer with Axios, and provides real-time updates through SWR polling. It can be wrapped in Electron for a desktop application.

### Authentication & Authorization

Nimhawk uses JWT bearer tokens stored in browser localStorage for session management and authorization. Tokens are verified on all protected API endpoints. Default credentials are set in `config.toml`.

### Database Schema

Key tables include `nimplants` (implant metadata), `tasks` (queued commands), `console` (command history), `downloads` (files retrieved), `file_transfers` (audit log), `workspaces` (implant grouping), `users` (operator credentials), and `chain_relationships` (relay topology).

### Communication Protocol

Implants register and periodically check in with the server for tasks, submitting results with encrypted payloads. Operators interact via authenticated REST API requests, queuing commands for implants, and receiving results via SWR polling. Encryption layers include an initial XOR key, unique per-implant XOR keys, and optional AES-CTR.

### HTTP Relay System

Nimhawk features a pure HTTP-over-HTTP relay system for N-level agent chains, where relays blindly forward HTTP requests without decrypting end-to-end encrypted payloads between agents and the C2.

**Design Principles:**
- **Single RELAY_CHAIN Define**: Unifies target selection and X-Next-Hop header injection.
- **Minimal Relay Intelligence**: Relays decrypt only routing headers, not agent payloads.
- **End-to-End Encryption**: Keys are shared only between C2 and the final agent.
- **Multi-Hop Support**: Supports arbitrary depth relay chains.
- **Dynamic Relay Start**: Relay servers can be initiated at runtime via operator commands.

**Core Components:**
- `multi_implant/core/http_relay.nim`: HTTP relay server.
- `multi_implant/core/webClientListener.nim`: Agent HTTP client, which always connects to the first hop in `RELAY_CHAIN`.
- `multi_implant/core/relay_launcher.nim`: Asynchronously starts the relay server.
- `multi_implant/core/cmdParser.nim`: Detects and parses `relay <PORT>` commands.
- `multi_implant/main.nim`: Orchestrates implant operations and dynamically launches the relay server.
- `server/src/servers/implants_api/implants_server_init.py`: C2 endpoint that reads `X-Relay-GUID` to establish `chain_relationships`.

### Multi-Platform Support

Implants support Windows x64, macOS (ARM64, x64), and Linux (x64, ARM, ARM64, MIPS), with cross-compilation capabilities. The frontend can be packaged for macOS, Windows, and Linux using Electron.

## External Dependencies

### Backend Services
- **Flask**: Web framework
- **Gevent**: WSGI server
- **Cryptography**: Crypto primitives
- **PyCryptoDome**: AES encryption
- **APSW**: SQLite wrapper
- **TOML**: Configuration parsing

### Frontend Services
- **Next.js**: React framework
- **Mantine**: UI component library
- **Axios**: HTTP client
- **SWR**: Data fetching and caching
- **React Flow**: Network topology visualization
- **Electron**: Desktop application packaging

### Build Tools
- **Nim**: Implant compilation
- **Nimble**: Nim package manager
- **MinGW-w64**: Cross-compilation
- **Node.js**: Frontend build tooling
- **Python 3.11**: Backend runtime
- **Zig**: Cross-platform C compiler wrapper
## HTTP Relay System - Detailed Documentation

### Recent Changes (September 30, 2025)
- **Removed**: ~1500 lines of legacy relay protocol code from multi_implant/main.nim
- **Unified**: RELAY_CHAIN define now controls both target selection and X-Next-Hop header injection
- **Deprecated**: RELAY_CHAIN_TARGET removed (use RELAY_CHAIN only)
- **Simplified**: httpHandler uses only HTTP relay system (no dual-mode logic)
- **Verified**: Successful compilation of Darwin ARM64 binary (99827 lines)
- **Enhanced UI**: Added "Relay Information" section to implant dashboard (Network tab) with ON/OFF status indicators
  - Relay Server: Shows status with green/gray dot, displays IP:PORT when ON
  - Relay Client: Shows status with green/gray dot, displays parent IP:PORT (ID) when ON
- **API Enhancement**: `/api/nimplants/<guid>` endpoint now includes comprehensive relay information:
  - `relay_role`: Role of the implant (RELAY_SERVER, RELAY_CLIENT, or STANDARD)
  - `relay_parent`: GUID of the parent relay
  - `relay_parent_ip`: Internal IP of the parent relay
  - `relay_parent_port`: Listening port of the parent relay
  - `relay_listening_port`: Listening port if this implant is a relay server
- **UI Component**: `NimplantDrawer.tsx` displays relay status with visual indicators and detailed connection information
- **Security Fix**: C2 URL extraction from RELAY_CHAIN for runtime relay servers
  - When a relay client (compiled with RELAY_CHAIN) starts a relay server at runtime via `relay <PORT>` command
  - C2 URL is automatically extracted from the last hop in RELAY_CHAIN
  - This allows relay clients to become relay servers without having C2 URL compiled in
  - Resolves "No C2 configured" errors when relays try to forward to C2

### Multi-Hop Behavior Example (3-Hop Chain)

**Scenario**: Agent → Relay1 → Relay2 → C2

**Step 1: Agent sends request**
- Target URL: `http://relay1.com:8080/register`
- X-Next-Hop: `<encrypted:"relay1.com:8080,relay2.com:8080,c2.com:5000">`
- X-Relay-GUID: None (not a relay)
- Payload: Encrypted with XOR+AES (only C2 can decrypt)

**Step 2: Relay1 receives and forwards**
- Decrypts X-Next-Hop → "relay1.com:8080,relay2.com:8080,c2.com:5000"
- Pops first hop (itself) → remainder: "relay2.com:8080,c2.com:5000"
- Re-encrypts remainder → new X-Next-Hop
- Forwards to: `http://relay2.com:8080/register`
- Injects X-Relay-GUID: `<encrypted:relay1_guid>`
- Payload: Unchanged (still encrypted for C2)

**Step 3: Relay2 receives and forwards**
- Decrypts X-Next-Hop → "relay2.com:8080,c2.com:5000"
- Pops first hop (itself) → remainder: "c2.com:5000"
- Re-encrypts remainder → new X-Next-Hop
- Forwards to: `http://c2.com:5000/register`
- Replaces X-Relay-GUID: `<encrypted:relay2_guid>` (strips Relay1's GUID)
- Payload: Unchanged

**Step 4: C2 receives request**
- Decrypts agent payload (has matching XOR+AES keys)
- Reads X-Relay-GUID → identifies immediate parent (relay2)
- Stores relationship in chain_relationships table
- Response flows back through same chain in reverse

### Compilation Variables

| Variable | Type | Required | Description | Example |
|----------|------|----------|-------------|---------|
| RELAY_CHAIN | string | No | Comma-separated relay hops ending with C2. Controls target URL and X-Next-Hop header. | `relay1.com:8080,c2.com:5000` |
| RELAY_PORT | int | No | Port for compile-time relay server start | `8080` |
| DEBUG | int | No | Enable debug logging (0 or 1) | `1` |
| INITIAL_XOR_KEY | int | Yes | Shared XOR key for header encryption (auto-generated) | `330699173` |

**Note**: RELAY_CHAIN_TARGET was removed. Use RELAY_CHAIN for all relay configuration.

### Build Examples

```bash
# Standard agent (no relay)
make darwin_arm64 DEBUG=1

# Single-hop relay (Agent → Relay1 → C2)
make darwin_arm64 RELAY_CHAIN=relay1.com:8080,c2.com:5000 DEBUG=1

# Two-hop relay (Agent → Relay1 → Relay2 → C2)
make darwin_arm64 RELAY_CHAIN=relay1.com:8080,relay2.com:8080,c2.com:5000 DEBUG=1

# Hybrid agent (relay client + relay server)
make darwin_arm64 RELAY_CHAIN=relay1.com:8080,c2.com:5000 RELAY_PORT=8080 DEBUG=1

# Windows build with relay
make windows_x64 RELAY_CHAIN=relay1.com:8080,c2.com:5000 DEBUG=1
```

### Operator Workflow for Multi-Hop Deployment

**Objective**: Deploy 3-hop chain (Agent → Relay1 → Relay2 → C2)

1. **Deploy Relay1** (standard agent on Target1)
   ```bash
   make darwin_arm64 DEBUG=1
   # Deploy to Target1, verify registration in Web UI
   ```

2. **Start Relay1 server** (runtime command)
   - In Web UI, send command to Relay1: `relay 8080`
   - Verify console output: "HTTP Relay server started on port 8080"

3. **Deploy Relay2** (relay client on Target2)
   ```bash
   make darwin_arm64 RELAY_CHAIN=target1.com:8080,c2.com:5000 DEBUG=1
   # Deploy to Target2, it will connect through Relay1
   ```

4. **Start Relay2 server** (runtime command)
   - In Web UI, send command to Relay2: `relay 8080`
   - Verify console output: "HTTP Relay server started on port 8080"

5. **Deploy final agent** (relay client on Target3)
   ```bash
   make darwin_arm64 RELAY_CHAIN=target2.com:8080,target1.com:8080,c2.com:5000 DEBUG=1
   # Deploy to Target3, it will connect through Relay2 → Relay1
   ```

6. **Verify topology**
   - Check Web UI Network Topology page
   - Query chain_relationships table in database
   - Verify X-Relay-GUID headers in debug logs

### Runtime Relay Start (`relay <PORT>` Command)

**Workflow:**
1. **Operator sends command** via Web UI: `relay 8080`
2. **cmdParser detects** command in core/cmdParser.nim
3. **Returns marker**: `RELAY_START:8080`
4. **main.nim detects** marker at line 1477
5. **Calls**: `relay_launcher.startRelayServerAsync(listener.id)`
6. **Server starts** on port 8080 using real implant GUID
7. **Console output**: "HTTP Relay server started on port 8080"

**Prerequisites:**
- Agent must be registered with C2 (has valid GUID)
- Port must be available (not in use)
- Agent must have network permissions to bind port

**Verification:**
- Check console output for "HTTP Relay server started"
- Test connectivity: deploy another agent with RELAY_CHAIN pointing to this relay
- Verify in Web UI that downstream agent registers through relay

### Topology Verification

**Method 1: Web UI**
- Navigate to "Network Topology" page
- Visual representation shows relay chains
- Hover over nodes to see GUID and parent relationships

**Method 2: Database Query**
```sql
SELECT parent_guid, child_guid, relationship_type
FROM chain_relationships
ORDER BY created_at DESC;
```

**Method 3: Debug Logs**
- Enable DEBUG=1 in build
- Check console output for:
  - "Using first relay hop as target: relay1.com:8080"
  - "Added X-Next-Hop header for relay chain"
  - "X-Relay-GUID: <encrypted_guid>"

**Method 4: End-to-End Test**
1. Deploy 2-hop chain (Agent → Relay → C2)
2. Send command to agent via Web UI: `whoami`
3. Verify result appears in console
4. Check debug logs on both agent and relay for header propagation

### Troubleshooting

**Issue**: Agent connects directly to C2 instead of relay
- **Cause**: RELAY_CHAIN not defined or formatted incorrectly
- **Solution**: Verify make command includes `RELAY_CHAIN=relay1.com:8080,c2.com:5000`

**Issue**: Relay server fails to start
- **Cause**: Port already in use or insufficient permissions
- **Solution**: Try different port or check system permissions

**Issue**: Agent registers but commands don't execute
- **Cause**: Relay not forwarding X-Next-Hop correctly
- **Solution**: Enable DEBUG=1 and check logs for header consumption

**Issue**: X-Relay-GUID not appearing in chain_relationships
- **Cause**: C2 not reading header or encryption mismatch
- **Solution**: Verify INITIAL_XOR_KEY matches between agent and C2
