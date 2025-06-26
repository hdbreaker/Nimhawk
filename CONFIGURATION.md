# Configuration Reference

This guide provides comprehensive information about configuring Nimhawk for different deployment scenarios.

## Table of Contents

- [Overview](#overview)
- [Configuration File Structure](#configuration-file-structure)
- [Core Server Settings](#core-server-settings)
- [Implant Settings](#implant-settings)
- [Authentication Configuration](#authentication-configuration)
- [Advanced Configuration](#advanced-configuration)
- [Environment Variables](#environment-variables)
- [Configuration Examples](#configuration-examples)
- [Security Considerations](#security-considerations)

## Overview

Nimhawk uses a TOML configuration file (`config.toml`) to manage all server and implant settings. Before using Nimhawk, you must configure this file by copying the example configuration:

```bash
cp config.toml.example config.toml
```

## Configuration File Structure

The configuration file is organized into several sections:

```toml
[admin_api]        # Admin API server settings
[implants_server]  # Implant listener settings  
[implant]          # Implant compilation settings
[auth]             # Authentication settings
[[auth.users]]     # User account definitions
```

## Core Server Settings

### Admin API Configuration

The Admin API serves the web interface and handles operator requests.

```toml
[admin_api]
ip = "127.0.0.1"    # IP address to bind to
port = 9669         # Port for the Admin API server
```

#### Admin API Settings Reference

| Setting | Default | Description | Example |
|---------|---------|-------------|---------|
| `ip` | `127.0.0.1` | Admin API bind address | `0.0.0.0` (all interfaces) |
| `port` | `9669` | Admin API port | `8080` |

### Implants Server Configuration

The Implants Server handles communication with deployed implants.

```toml
[implants_server]
type = "HTTP"                    # Protocol: HTTP or HTTPS
hostname = ""                    # Optional hostname
port = 80                        # Listener port
registerPath = "/api/register"   # Registration endpoint
taskPath = "/api/task"          # Task retrieval endpoint
resultPath = "/api/result"      # Result submission endpoint
reconnectPath = "/api/reconnect" # Reconnection endpoint

# HTTPS settings (only needed if type = "HTTPS")
sslCertPath = "server.crt"      # SSL certificate path
sslKeyPath = "server.key"       # SSL private key path
```

#### Implants Server Settings Reference

| Setting | Default | Description | Example |
|---------|---------|-------------|---------|
| `type` | `HTTP` | Protocol type | `HTTPS` |
| `hostname` | `""` | Optional hostname for connections | `c2.example.com` |
| `port` | `80` | Listener port | `443` (for HTTPS) |
| `registerPath` | `/api/register` | Initial registration endpoint | `/reg` |
| `taskPath` | `/api/task` | Task retrieval endpoint | `/tasks` |
| `resultPath` | `/api/result` | Result submission endpoint | `/results` |
| `reconnectPath` | `/api/reconnect` | Reconnection endpoint | `/reconnect` |
| `sslCertPath` | `""` | SSL certificate file path | `/path/to/cert.pem` |
| `sslKeyPath` | `""` | SSL private key file path | `/path/to/key.pem` |

## Implant Settings

These settings control how implants are compiled and how they behave.

```toml
[implant]
listenerIp = "127.0.0.1"                    # IP for implants to connect back to
riskyMode = false                            # Enable risky commands
sleepMask = true                             # Use sleep masking (exe only)
sleepTime = 10                               # Sleep time in seconds
sleepJitter = 20                             # Jitter percentage (0-100)
killDate = "2025-12-31"                      # Self-termination date
userAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36" # HTTP User-Agent
httpAllowCommunicationKey = "your-secret-key" # Communication key
```

### Implant Settings Reference

| Setting | Default | Description | Example |
|---------|---------|-------------|---------|
| `listenerIp` | `127.0.0.1` | Public IP for implant callbacks | `192.168.1.100` |
| `riskyMode` | `false` | Enable advanced but detectable commands | `true` |
| `sleepMask` | `true` | Use sleep masking techniques | `false` |
| `sleepTime` | `10` | Default sleep time in seconds | `30` |
| `sleepJitter` | `20` | Jitter percentage to randomize sleep | `50` |
| `killDate` | `"2025-12-31"` | Self-termination date (yyyy-MM-dd) | `"2024-06-30"` |
| `userAgent` | Standard Chrome UA | Custom User-Agent string | Custom string |
| `httpAllowCommunicationKey` | Auto-generated | Machine-to-machine auth key | `"MySecretKey123"` |

### Risky Mode Commands

When `riskyMode = true`, these additional commands become available:
- `execute-assembly` - Execute .NET assemblies in memory
- `inline-execute` - Execute raw shellcode
- `powershell` - Execute PowerShell commands
- `shell` - Execute shell commands
- `shinject` - Inject shellcode into processes

> ⚠️ **Warning**: Risky mode commands may be more easily detected by security software.

## Authentication Configuration

Nimhawk includes a comprehensive authentication system for the web interface.

```toml
[auth]
enabled = true           # Enable authentication
session_duration = 24   # Session duration in hours

# User accounts
[[auth.users]]
email = "admin@nimhawk.com"
password = "P4ssw0rd123$"
admin = true

[[auth.users]]
email = "operator@nimhawk.com"
password = "Op3rat0r456!"
admin = false
```

### Authentication Settings Reference

| Setting | Default | Description | Example |
|---------|---------|-------------|---------|
| `enabled` | `true` | Enable/disable authentication | `false` |
| `session_duration` | `24` | Session duration in hours | `8` |

### User Account Fields

| Field | Required | Description | Example |
|-------|----------|-------------|---------|
| `email` | Yes | User email for login | `user@example.com` |
| `password` | Yes | User password | `SecurePassword123!` |
| `admin` | Yes | Admin privileges (true/false) | `true` |

### Password Requirements

- Minimum 8 characters
- At least one uppercase letter
- At least one lowercase letter
- At least one number
- At least one special character

## Advanced Configuration

### Custom Communication Paths

You can customize all communication endpoints:

```toml
[implants_server]
registerPath = "/custom/register"
taskPath = "/custom/task"
resultPath = "/custom/result"
reconnectPath = "/custom/reconnect"
```

### HTTPS Configuration

For production deployments, use HTTPS:

```toml
[implants_server]
type = "HTTPS"
port = 443
sslCertPath = "/path/to/certificate.crt"
sslKeyPath = "/path/to/private.key"
```

#### Generating SSL Certificates

```bash
# Self-signed certificate (development only)
openssl req -x509 -newkey rsa:4096 -keyout key.pem -out cert.pem -days 365 -nodes

# Let's Encrypt certificate (production)
certbot certonly --standalone -d your-domain.com
```

### Sleep Masking Configuration

Sleep masking helps evade detection during implant dormancy:

```toml
[implant]
sleepMask = true    # Enable sleep masking
sleepTime = 30      # Base sleep time
sleepJitter = 25    # Add randomization
```

> 📝 **Note**: Sleep masking only works with executable implants, not DLL or shellcode formats.

### Kill Date Configuration

Set an automatic termination date for implants:

```toml
[implant]
killDate = "2024-12-31"  # Format: yyyy-MM-dd
```

After this date, implants will automatically terminate to prevent long-term persistence.

## Environment Variables

### Frontend Configuration

Create a `.env` file in `server/admin_web_ui/` for frontend configuration:

```bash
# Server endpoints
NEXT_PUBLIC_NIMHAWK_ADMIN_SERVER_IP=http://your-nimhawk-admin-api-server.com
NEXT_PUBLIC_NIMHAWK_ADMIN_SERVER_PORT=9669
NEXT_PUBLIC_NIMHAWK_IMPLANT_SERVER_IP=http://your-nimhawk-implants-api-server.com
NEXT_PUBLIC_NIMHAWK_IMPLANT_SERVER_PORT=80
```

### Environment Variables Reference

| Variable | Description | Example |
|----------|-------------|---------|
| `NEXT_PUBLIC_NIMHAWK_ADMIN_SERVER_IP` | Admin API server URL | `http://192.168.1.100` |
| `NEXT_PUBLIC_NIMHAWK_ADMIN_SERVER_PORT` | Admin API server port | `9669` |
| `NEXT_PUBLIC_NIMHAWK_IMPLANT_SERVER_IP` | Implant listener URL | `http://192.168.1.100` |
| `NEXT_PUBLIC_NIMHAWK_IMPLANT_SERVER_PORT` | Implant listener port | `80` |

## Configuration Examples

### Local Development
```toml
[admin_api]
ip = "127.0.0.1"
port = 9669

[implants_server]
type = "HTTP"
port = 80

[implant]
listenerIp = "127.0.0.1"
riskyMode = true
sleepTime = 5
sleepJitter = 10

[auth]
enabled = true
session_duration = 24

[[auth.users]]
email = "dev@nimhawk.com"
password = "DevPassword123!"
admin = true
```

### Production Environment
```toml
[admin_api]
ip = "0.0.0.0"
port = 9669

[implants_server]
type = "HTTPS"
hostname = "c2.example.com"
port = 443
sslCertPath = "/etc/ssl/certs/nimhawk.crt"
sslKeyPath = "/etc/ssl/private/nimhawk.key"

[implant]
listenerIp = "203.0.113.10"
riskyMode = false
sleepTime = 60
sleepJitter = 30
killDate = "2024-12-31"
userAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
httpAllowCommunicationKey = "SuperSecretProductionKey2024!"

[auth]
enabled = true
session_duration = 8

[[auth.users]]
email = "admin@company.com"
password = "ProductionAdminPass123!"
admin = true

[[auth.users]]
email = "operator1@company.com"
password = "OperatorPass456!"
admin = false
```

### Red Team Engagement
```toml
[admin_api]
ip = "0.0.0.0"
port = 9669

[implants_server]
type = "HTTPS"
hostname = "update.legitimate-domain.com"
port = 443
registerPath = "/api/v1/check"
taskPath = "/api/v1/updates"
resultPath = "/api/v1/report"
reconnectPath = "/api/v1/sync"

[implant]
listenerIp = "185.199.108.153"  # GitHub Pages IP for blending
riskyMode = true
sleepTime = 300
sleepJitter = 50
killDate = "2024-06-30"
userAgent = "Windows-Update-Agent/10.0.10011.16384 Client-Protocol/2.33"
httpAllowCommunicationKey = "G7h9K2mP4qR8sT1vW3xZ6bC9dF2gH5jL"

[auth]
enabled = true
session_duration = 12

[[auth.users]]
email = "redteam-lead@engagement.local"
password = "RedTeamSecure2024!"
admin = true

[[auth.users]]
email = "operator@engagement.local"
password = "OperatorSecure2024!"
admin = false
```

### Multi-Redirector Setup
```toml
[admin_api]
ip = "192.168.1.200"  # C2 Server IP
port = 9669

[implants_server]
type = "HTTPS"
port = 443

[implant]
listenerIp = "192.168.1.100"  # First redirector IP
riskyMode = false
sleepTime = 120
sleepJitter = 40
```

## Security Considerations

### Network Security
- Use HTTPS in production environments
- Implement proper firewall rules
- Consider using redirectors to hide your C2 infrastructure
- Use non-standard ports when possible

### Authentication Security
- Change default passwords immediately
- Use strong passwords meeting complexity requirements
- Limit session duration for operational security
- Regular password rotation for long-term engagements

### Operational Security
- Use realistic User-Agent strings
- Implement appropriate sleep times with jitter
- Set kill dates for time-boxed engagements
- Use legitimate-looking domain names and paths

### Communication Security
- Generate strong communication keys
- Rotate keys regularly
- Use custom endpoint paths
- Implement proper request/response validation

## Validation and Testing

### Configuration Validation
```bash
# Test configuration syntax
python3 -c "import toml; toml.load('config.toml')"

# Test server startup
python3 nimhawk.py server --dry-run
```

### Network Testing
```bash
# Test admin API
curl http://localhost:9669/api/health

# Test implant listener
curl http://localhost:80/api/register
```

### Authentication Testing
```bash
# Test login endpoint
curl -X POST http://localhost:9669/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email": "admin@nimhawk.com", "password": "P4ssw0rd123$"}'
```

## Troubleshooting Configuration Issues

### Common Problems

#### Invalid TOML Syntax
```bash
# Validate TOML syntax
python3 -c "import toml; print('Valid TOML') if toml.load('config.toml') else print('Invalid TOML')"
```

#### Port Conflicts
```bash
# Check if ports are in use
netstat -an | grep :9669
netstat -an | grep :80
```

#### SSL Certificate Issues
```bash
# Verify certificate
openssl x509 -in certificate.crt -text -noout

# Test SSL connection
openssl s_client -connect localhost:443
```

#### Authentication Problems
- Verify password complexity requirements
- Check user configuration syntax
- Ensure session duration is reasonable
- Validate email format

For additional help, see the [main troubleshooting guide](README.md#troubleshooting) or [installation guide](INSTALLATION.md#troubleshooting). 