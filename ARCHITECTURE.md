# Architecture Overview

This document provides a detailed technical overview of Nimhawk's architecture, design patterns, and implementation details.

## Table of Contents

- [High-Level Architecture](#high-level-architecture)
- [Component Architecture](#component-architecture)
- [Communication Protocols](#communication-protocols)
- [Security Architecture](#security-architecture)
- [Data Flow](#data-flow)
- [Database Schema](#database-schema)
- [File Structure](#file-structure)
- [API Design](#api-design)
- [Development Architecture](#development-architecture)

## High-Level Architecture

```
┌────────────────────────────────────────┐              ┌───────────────────┐
│                                        │              │                   │
│  OPERATOR MACHINE                      │              │  TARGET MACHINE   │
│                                        │              │                   │
│  ┌───────────┐                         │              │  ┌───────────┐    │
│  │ Web UI    │                         │              │  │  Nimhawk  │    │
│  │ (React)   │                         │              │  │  Implant  │    │
│  └───────────┘                         │              │  └─────┬─────┘    │
│      │                                 │              │        │          │
│      │  HTTPS REST API                 │              │        │          │
│      │                                 │              │        │          │
│      │                                 │              │        │          │
│  ┌───│─ ──────────────────────┐        │              │        │          │
│  │   │  PYTHON BACKEND        │        │              │        │          │
│  │  ┌▼─────────────────┐      │        │              │        │          │
│  │  │ Admin API Server │      │        │              │        │          │
│  │  └──────────────────┘      │        │              │        │          │
│  │                            │        │              │        │          │
│  │  ┌──────────────────┐      │        │              │        │          │
│  │  │ Implants Server  │◄─────┼────────┼──────────────┼────────┘          │
│  │  └──────────────────┘      │        │              │   HTTP/HTTPS      │
│  └───────────┬────────────────┘        │              │                   │
│              │                         │              │                   │
│              ▼                         │              │                   │
│  ┌───────────────────┐                 │              │                   │
│  │    nimhawk.db     │                 │              │                   │
│  │    (SQLite)       │                 │              │                   │
│  └───────────────────┘                 │              │                   │
│                                        │              │                   │
└────────────────────────────────────────┘              └───────────────────┘
```

### Core Components

1. **Web UI (Frontend)**: React-based user interface
2. **Admin API Server**: REST API for operator interactions
3. **Implants Server**: Communication endpoint for implants
4. **Database**: SQLite database for data persistence
5. **Implant**: Nim-based agent running on target systems

## Component Architecture

### Frontend Architecture (React/Next.js)

```
admin_web_ui/
├── pages/                 # Next.js pages (routing)
│   ├── index.js          # Dashboard
│   ├── implants/         # Implant management
│   ├── server/           # Server information
│   └── downloads/        # File management
├── components/           # Reusable React components
│   ├── Layout/          # Page layouts
│   ├── Implant/         # Implant-specific components
│   ├── Console/         # Command console
│   └── Common/          # Shared components
├── hooks/               # Custom React hooks
├── utils/               # Utility functions
├── styles/              # CSS and styling
└── public/              # Static assets
```

#### Frontend Design Patterns

- **Component Composition**: Reusable UI components
- **Custom Hooks**: Shared stateful logic
- **Context API**: Global state management
- **Server-Side Rendering**: Next.js SSR for performance
- **Real-time Updates**: WebSocket connections for live data

### Backend Architecture (Python/Flask)

```
server/
├── main.py                    # Application entry point
├── servers/                   # Server implementations
│   ├── admin_api/            # Admin API server
│   │   ├── admin_server_init.py
│   │   ├── routes/           # API endpoints
│   │   └── middleware/       # Authentication, CORS
│   └── implants_api/         # Implant communication server
│       ├── implants_server_init.py
│       └── handlers/         # Request handlers
├── core/                     # Core business logic
│   ├── database/            # Database operations
│   ├── models/              # Data models
│   ├── services/            # Business services
│   └── utils/               # Utility functions
├── config/                   # Configuration management
└── tests/                    # Unit and integration tests
```

#### Backend Design Patterns

- **Separation of Concerns**: Distinct API servers
- **Repository Pattern**: Database abstraction
- **Service Layer**: Business logic encapsulation
- **Middleware Pattern**: Cross-cutting concerns
- **Factory Pattern**: Object creation

### Implant Architecture (Nim)

```
implant/
├── src/
│   ├── nimhawk.nim          # Main implant entry point
│   ├── core/                # Core functionality
│   │   ├── communication.nim # C2 communication
│   │   ├── crypto.nim       # Encryption/decryption
│   │   └── utils.nim        # Utility functions
│   ├── commands/            # Command implementations
│   │   ├── basic/           # Basic commands
│   │   ├── risky/           # Advanced commands
│   │   └── system/          # System operations
│   └── evasion/             # Evasion techniques
│       ├── sleep_mask.nim   # Sleep masking
│       └── anti_debug.nim   # Anti-debugging
├── config/                  # Build configurations
└── bin/                     # Compiled binaries
```

#### Implant Design Patterns

- **Command Pattern**: Modular command execution
- **Strategy Pattern**: Different evasion techniques
- **Observer Pattern**: Event handling
- **State Machine**: Connection state management

## Communication Protocols

### HTTP/HTTPS Protocol

Nimhawk uses HTTP/HTTPS for all communications with custom headers for authentication and routing.

#### Custom Headers

| Header | Purpose | Example |
|--------|---------|---------|
| `X-Request-ID` | Implant UUID | `a1b2c3d4-e5f6-7890-abcd-ef1234567890` |
| `Content-MD5` | Task ID | `task-12345` |
| `X-Correlation-ID` | Communication key | `secret-key-12345` |
| `X-Robots-Tag` | Workspace UUID | `workspace-uuid-67890` |

#### Communication Flow

```
1. Implant Registration
   POST /api/register
   Headers: X-Correlation-ID, X-Robots-Tag
   Body: Encrypted implant metadata

2. Task Retrieval
   GET /api/task
   Headers: X-Request-ID, X-Correlation-ID
   Response: Encrypted command data

3. Result Submission
   POST /api/result
   Headers: X-Request-ID, Content-MD5, X-Correlation-ID
   Body: Encrypted command results

4. Reconnection
   POST /api/reconnect
   Headers: X-Request-ID, X-Correlation-ID
   Body: Encrypted reconnection data
```

### Encryption Protocol

#### Data Encryption
- **Algorithm**: XOR encryption (configurable)
- **Key Exchange**: HTTP communication key
- **Compression**: zlib compression for large payloads
- **Encoding**: Base64 encoding for transport

#### Implementation
```nim
# Nim encryption example
proc encryptData(data: string, key: string): string =
    let compressed = compress(data)
    let encrypted = xorEncrypt(compressed, key)
    return base64.encode(encrypted)
```

### Reconnection Protocol

Nimhawk implements a robust reconnection mechanism:

1. **Exponential Backoff**: Increasing delays between attempts
2. **Registry Cleanup**: Remove old entries before reconnection
3. **State Preservation**: Maintain command queue during disconnection
4. **Error Handling**: Graceful handling of network failures

## Security Architecture

### Authentication System

#### Dual Authentication
1. **Web UI Authentication**: Session-based for operators
2. **Implant Authentication**: Pre-shared key with custom headers

#### Authentication Flow
```
1. Operator Login
   POST /api/auth/login
   Body: {"email": "user@example.com", "password": "password"}
   Response: {"token": "jwt-token", "expires": "timestamp"}

2. Session Validation
   GET /api/protected-endpoint
   Headers: Authorization: Bearer jwt-token

3. Implant Authentication
   All implant requests include:
   Headers: X-Correlation-ID: pre-shared-key
```

### Security Headers

All API responses include security headers:
```
X-Content-Type-Options: nosniff
X-Frame-Options: DENY
X-XSS-Protection: 1; mode=block
Strict-Transport-Security: max-age=31536000
Content-Security-Policy: default-src 'self'
```

### Data Protection

- **Encryption at Rest**: Database encryption (optional)
- **Encryption in Transit**: HTTPS/TLS
- **Input Validation**: All user inputs sanitized
- **Output Encoding**: Prevent XSS attacks
- **SQL Injection Prevention**: Parameterized queries

## Data Flow

### Command Execution Flow

```
1. Operator Input
   ┌─────────────┐
   │ Web UI      │ ──── Command Input
   └─────────────┘

2. API Processing
   ┌─────────────┐
   │ Admin API   │ ──── Validate & Queue
   └─────────────┘

3. Database Storage
   ┌─────────────┐
   │ SQLite DB   │ ──── Store Command
   └─────────────┘

4. Implant Retrieval
   ┌─────────────┐
   │ Implant API │ ──── Fetch Command
   └─────────────┘

5. Target Execution
   ┌─────────────┐
   │ Implant     │ ──── Execute Command
   └─────────────┘

6. Result Return
   ┌─────────────┐
   │ Implant API │ ──── Submit Results
   └─────────────┘

7. Display Results
   ┌─────────────┐
   │ Web UI      │ ──── Show Output
   └─────────────┘
```

### File Transfer Flow

```
Upload Flow:
Web UI → Admin API → Database → Implant API → Implant → Target File System

Download Flow:
Target File System → Implant → Implant API → Database → Admin API → Web UI
```

## Database Schema

### Core Tables

#### implants
```sql
CREATE TABLE implants (
    id TEXT PRIMARY KEY,
    hostname TEXT,
    username TEXT,
    operating_system TEXT,
    process_name TEXT,
    process_id INTEGER,
    ip_address TEXT,
    external_ip TEXT,
    first_seen TIMESTAMP,
    last_seen TIMESTAMP,
    status TEXT,
    workspace_id TEXT
);
```

#### commands
```sql
CREATE TABLE commands (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    implant_id TEXT,
    command TEXT,
    arguments TEXT,
    timestamp TIMESTAMP,
    status TEXT,
    result TEXT,
    FOREIGN KEY (implant_id) REFERENCES implants (id)
);
```

#### files
```sql
CREATE TABLE files (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    implant_id TEXT,
    filename TEXT,
    filepath TEXT,
    size INTEGER,
    file_data BLOB,
    upload_timestamp TIMESTAMP,
    file_type TEXT,
    FOREIGN KEY (implant_id) REFERENCES implants (id)
);
```

#### workspaces
```sql
CREATE TABLE workspaces (
    id TEXT PRIMARY KEY,
    name TEXT,
    description TEXT,
    created_at TIMESTAMP,
    active BOOLEAN
);
```

### Database Operations

#### Connection Management
```python
class DatabaseManager:
    def __init__(self, db_path):
        self.db_path = db_path
        self.connection = None
    
    def get_connection(self):
        if not self.connection:
            self.connection = sqlite3.connect(self.db_path)
        return self.connection
```

#### Transaction Management
- Automatic transaction handling
- Connection pooling
- Error recovery
- Data integrity checks

## File Structure

### Project Organization

```
nimhawk/
├── README.md                 # Main documentation
├── INSTALLATION.md           # Installation guide
├── CONFIGURATION.md          # Configuration reference
├── DEPLOYMENT.md             # Deployment guide
├── ARCHITECTURE.md           # This document
├── DEVELOPERS.md             # Developer documentation
├── LICENSE                   # MIT license
├── Dockerfile               # Docker configuration
├── docker-compose.yml       # Docker Compose setup
├── config.toml.example      # Example configuration
├── nimhawk.py               # Main CLI interface
├── implant/                 # Nim implant source
│   ├── src/                 # Source code
│   ├── config/              # Build configurations
│   ├── nim.cfg              # Nim compiler settings
│   ├── nimhawk.nimble       # Nim package file
└── server/                  # Python backend
    ├── main.py              # Server entry point
    ├── requirements.txt     # Python dependencies
    ├── servers/             # API servers
    ├── core/                # Core business logic
    └── admin_web_ui/        # React frontend
        ├── package.json     # Node.js dependencies
        ├── pages/           # Next.js pages
        ├── components/      # React components
        └── electron/        # Electron configuration
```

### Module Dependencies

```
Frontend Dependencies:
├── React 18+
├── Next.js 13+
├── Electron (desktop app)
├── Axios (HTTP client)
├── Socket.io (real-time)
└── Tailwind CSS (styling)

Backend Dependencies:
├── Flask (web framework)
├── SQLite3 (database)
├── Cryptography (encryption)
├── Requests (HTTP client)
└── TOML (configuration)

Implant Dependencies:
├── Nim standard library
├── HTTPClient (networking)
├── JSON (serialization)
├── Base64 (encoding)
└── OS (system operations)
```

## API Design

### RESTful API Structure

#### Admin API Endpoints

```
Authentication:
POST   /api/auth/login      # User login
POST   /api/auth/logout     # User logout
GET    /api/auth/verify     # Token verification

Implants:
GET    /api/implants        # List all implants
GET    /api/implants/:id    # Get specific implant
DELETE /api/implants/:id    # Delete implant
POST   /api/implants/:id/commands  # Send command

Commands:
GET    /api/commands        # List commands
GET    /api/commands/:id    # Get command details
POST   /api/commands        # Create command

Files:
GET    /api/files           # List files
GET    /api/files/:id       # Download file
POST   /api/files           # Upload file
DELETE /api/files/:id       # Delete file

Workspaces:
GET    /api/workspaces      # List workspaces
POST   /api/workspaces      # Create workspace
PUT    /api/workspaces/:id  # Update workspace
DELETE /api/workspaces/:id  # Delete workspace
```

#### Implant API Endpoints

```
Registration:
POST   /api/register        # Initial registration

Communication:
GET    /api/task            # Get pending tasks
POST   /api/result          # Submit results
POST   /api/reconnect       # Reconnect implant

File Transfer:
GET    /api/download/:id    # Download file
POST   /api/upload          # Upload file
```

### Response Format

#### Standard Response Structure
```json
{
    "success": true,
    "data": { ... },
    "message": "Success message",
    "timestamp": "2024-01-01T00:00:00Z"
}
```

#### Error Response Structure
```json
{
    "success": false,
    "error": {
        "code": "ERROR_CODE",
        "message": "Error description",
        "details": { ... }
    },
    "timestamp": "2024-01-01T00:00:00Z"
}
```

## Development Architecture

### Development Patterns

#### Modular Design
- **Separation of Concerns**: Each module has a single responsibility
- **Interface-Based Design**: Well-defined interfaces between components
- **Dependency Injection**: Configurable dependencies
- **Plugin Architecture**: Extensible command system

#### Code Organization
```
Core Principles:
1. Single Responsibility Principle
2. Open/Closed Principle
3. Dependency Inversion Principle
4. Interface Segregation Principle
```

### Testing Architecture

#### Test Structure
```
tests/
├── unit/                    # Unit tests
│   ├── test_models.py      # Model tests
│   ├── test_services.py    # Service tests
│   └── test_utils.py       # Utility tests
├── integration/             # Integration tests
│   ├── test_api.py         # API tests
│   └── test_database.py    # Database tests
└── e2e/                     # End-to-end tests
    └── test_workflow.py     # Complete workflow tests
```

#### Testing Strategies
- **Unit Testing**: Individual component testing
- **Integration Testing**: Component interaction testing
- **End-to-End Testing**: Full workflow testing
- **Security Testing**: Vulnerability assessment
- **Performance Testing**: Load and stress testing

### Build and Deployment Pipeline

#### CI/CD Pipeline
```yaml
# GitHub Actions example
name: Nimhawk CI/CD

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - name: Run tests
        run: |
          python -m pytest tests/
          
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - name: Build Docker image
        run: docker build -t nimhawk .
        
  deploy:
    runs-on: ubuntu-latest
    if: github.ref == 'refs/heads/main'
    steps:
      - name: Deploy to production
        run: echo "Deploy to production"
```

### Performance Considerations

#### Optimization Strategies
- **Database Indexing**: Optimize query performance
- **Connection Pooling**: Reuse database connections
- **Caching**: Redis/Memcached for frequently accessed data
- **Asynchronous Processing**: Background task processing
- **Load Balancing**: Distribute traffic across servers

#### Scalability Design
- **Horizontal Scaling**: Multiple server instances
- **Vertical Scaling**: Increased server resources
- **Database Sharding**: Distribute data across databases
- **CDN Integration**: Static asset delivery
- **Microservices**: Service decomposition

For implementation details and development guidelines, see [DEVELOPERS.md](DEVELOPERS.md). 