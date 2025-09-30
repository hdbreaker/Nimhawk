# Nimhawk C2 Framework

## Overview

Nimhawk is a command and control (C2) framework designed for educational and authorized red teaming purposes. It consists of:

- **Python backend server** - Handles implant communications and operator management
- **React/Next.js frontend** - Web-based operator interface
- **Nim-based implants** - Lightweight agents that run on target systems
- **SQLite database** - Stores implant data, commands, and session information

The system uses a client-server architecture where operators interact with implants through a web interface, sending commands and receiving results via HTTP/HTTPS channels.

## User Preferences

Preferred communication style: Simple, everyday language.

## Quick Setup

### Automated Setup (Recommended)

Run the automated setup script to configure the entire environment:

```bash
chmod +x setup.sh
./setup.sh
```

This script will:
- Detect if running in Replit or local environment
- Install Nim compiler (2.2.4+) and Nimble package manager
- Install Python dependencies from server/requirements.txt
- Install Nim dependencies (nimcrypto, parsetoml, puppy)
- Create config.toml from template if needed
- Configure Replit-specific settings (domain, ports)
- Create necessary directories for logs, downloads, uploads

### Manual Setup (Replit)

If you prefer manual setup in Replit:

1. **Python dependencies** are auto-installed via the python-3.11 module
2. **Nim installation**: Run `curl https://nim-lang.org/choosenim/init.sh -sSf | sh -s -- -y`
3. **Add Nim to PATH**: `export PATH="$HOME/.nimble/bin:$PATH"`
4. **Install Nim packages**: `nimble install -y nimcrypto parsetoml puppy`
5. **Update config.toml**: Set `port = 5000` and `implantCallbackIp` to your Replit domain

### Docker Setup

Build and run with Docker:

```bash
docker build -t nimhawk .
docker run -p 5000:5000 -p 8080:8080 nimhawk server
```

### Replit-Specific Configuration

Current Replit environment is configured with:
- **Admin API**: Port 5000 (public HTTPS on port 443)
- **Implants Server**: Port 8080 (internal, proxied through Admin API)
- **Domain**: Auto-detected and configured in config.toml
- **Workflow**: Backend automatically starts via `.replit` configuration

## System Architecture

### Backend Architecture

**Technology Stack:**
- Python 3.8+ with Flask for REST API
- SQLite database (via APSW) for data persistence
- Gevent for async request handling
- XOR and AES-CTR encryption for secure communications

**Core Components:**
1. **Admin API Server** (`server/src/servers/admin_api/`) - Serves the web UI and handles operator authentication/commands on port 5000 (Replit) or 9669 (local)
2. **Implants Server** (`server/src/servers/implants_api/`) - Listens for implant callbacks on configurable ports (8080 internal, proxied through port 5000 in Replit)
3. **Database Layer** (`server/src/config/db.py`) - SQLite schema with tables for implants, commands, tasks, downloads, workspaces, and users

**Design Decisions:**
- Single SQLite database file (`nimhawk.db`) for simplicity and portability
- XOR encryption with unique keys per implant for obfuscation
- Session-based authentication with JWT tokens stored in localStorage
- TOML configuration file (`config.toml`) as single source of truth for server settings

### Frontend Architecture

**Technology Stack:**
- Next.js 15.x with React 18
- Mantine UI component library v7
- SWR for data fetching and caching
- Electron wrapper for desktop application

**Core Design Patterns:**
1. **Static Site Generation** - Next.js exports static files to `out/` directory for production
2. **API Communication** - Centralized API layer (`modules/apiFetcher.ts`) with axios interceptors for auth
3. **Real-time Updates** - SWR polling (10s intervals) for implant status and console data
4. **Component Architecture** - Modular components for reusability (Console, NimplantDrawer, FilePreview, etc.)

**Key Files:**
- `config.ts` - Environment-based server URL configuration
- `modules/nimplant.ts` - Core API endpoints and data fetching logic
- `version.ts` - Centralized version management reading from package.json

### Authentication & Authorization

**Mechanism:**
- JWT bearer tokens for session management
- Tokens stored in browser localStorage
- Authorization header (`Bearer <token>`) on all authenticated requests
- Default credentials configured in `config.toml` under `[[auth.users]]`

**Security Considerations:**
- CORS enabled for cross-origin requests
- Credentials included in requests (`withCredentials: true`)
- Token verification on each protected API endpoint

### Database Schema

**Primary Tables:**
- `nimplants` - Implant metadata (GUID, hostname, IP, process info, check-in times)
- `tasks` - Commands queued for implants
- `console` - Command execution history and results
- `downloads` - Files retrieved from implants
- `file_transfers` - Audit log of all file operations
- `workspaces` - Logical groupings of implants for multi-tenancy
- `users` - Operator authentication credentials (bcrypt hashed passwords)

**Relationships:**
- Implants belong to workspaces (1:many)
- Tasks reference implants via GUID (many:1)
- Downloads link to implants for file tracking

### Communication Protocol

**Implant → Server Flow:**
1. Initial registration with XOR-encrypted metadata
2. Periodic check-ins for pending tasks (pull model)
3. Task result submission with encrypted payloads
4. File upload/download via dedicated endpoints

**Operator → Server Flow:**
1. Web UI sends authenticated REST API requests
2. Server validates JWT and processes commands
3. Commands queued in database for next implant check-in
4. Results streamed back to UI via SWR polling

**Encryption Layers:**
- Initial XOR key from `.xorkey` file for registration
- Per-implant unique XOR key for session isolation
- Optional AES-CTR for payload encryption (SOR crypto module)

### Multi-Platform Support

**Implant Compilation:**
- Primary target: Windows x64 (Nim compiled)
- Multi-platform support via `multi_implant/` directory (Linux x64/ARM/MIPS, macOS)
- Cross-compilation using MinGW-w64 (Linux → Windows)
- Build system uses `nimble` and custom Python builder script

**Desktop Application:**
- Electron wrapper for standalone deployment
- Scripts: `electron-dev`, `electron-build` for packaging
- Platform targets: macOS, Windows, Linux via electron-builder

## External Dependencies

### Backend Services
- **Flask** (3.0.3) - Web framework for REST API
- **Gevent** (24.2.1) - WSGI server with async capabilities
- **Cryptography** (43.0.0) - Modern crypto primitives
- **PyCryptoDome** (3.20.0) - AES encryption implementation
- **APSW** (3.49.1.0) - Advanced SQLite wrapper
- **TOML** (0.10.2) - Configuration file parsing

### Frontend Services
- **Next.js** (15.2.5) - React framework with SSG
- **Mantine** (7.11.2) - UI component library
- **Axios** (1.8.4) - HTTP client with interceptors
- **SWR** (2.2.5) - Data fetching and caching
- **React Flow** (11.11.4) - Network topology visualization
- **Electron** (32.2.0) - Desktop application packaging

### Build Tools
- **Nim** (2.2.4+) - Implant compilation language
- **Nimble** (0.18.2+) - Nim package manager
- **MinGW-w64** - Cross-compilation toolchain (for Windows targets)
- **Node.js 16+** - Frontend build tooling
- **Python 3.11** - Backend runtime (configured for Replit)

### Development Tools
- **Docker** - Containerized deployment option
- **electron-builder** (25.1.8) - Desktop app packaging
- **TypeScript** (5.5.4) - Type safety for frontend
- **ESLint** - Code quality enforcement

### Configuration Files
- `config.toml` - Server settings (IP, ports, paths, auth)
- `.xorkey` - Initial encryption key (generated on first run)
- `package.json` - Single source of truth for version (1.4.0)
- `nimhawk.db` - SQLite database file (auto-created)
- `setup.sh` - Automated environment setup script for Replit/Docker/local
- `.replit` - Replit-specific configuration (workflows, modules, ports)