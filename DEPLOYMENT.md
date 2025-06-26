# Deployment Guide

This guide covers various deployment scenarios for Nimhawk, from local development to production environments.

## Table of Contents

- [Overview](#overview)
- [Docker Deployment](#docker-deployment)
- [Production Deployment](#production-deployment)
- [Redirector Setup](#redirector-setup)
- [Desktop Application Deployment](#desktop-application-deployment)
- [Distributed Deployment](#distributed-deployment)
- [Security Considerations](#security-considerations)
- [Monitoring and Maintenance](#monitoring-and-maintenance)

## Overview

Nimhawk supports multiple deployment scenarios:

- **Local Development**: Single machine setup for testing and development
- **Docker Deployment**: Containerized deployment for consistency and isolation
- **Production Deployment**: Secure, scalable production environment
- **Distributed Deployment**: Frontend and backend on separate servers
- **Desktop Application**: Standalone Electron-based application

## Docker Deployment

> 📝 **Important**: Docker deployment is the simplest and recommended approach. The container handles all internal routing between frontend and backend services without requiring additional configuration like nginx reverse proxy.

### Building the Docker Image

```bash
# Clone the repository
git clone https://github.com/hdbreaker/nimhawk
cd nimhawk

# Build the Docker image
docker build -t nimhawk .
```

### Running Nimhawk in Docker

The container supports multiple operation modes:

```bash
# Full deployment (recommended)
docker run -it -p 3000:3000 -p 9669:9669 -p 80:80 -p 443:443 \
  -v nimhawk-data:/nimhawk/server \
  nimhawk full
```

### Available Docker Commands

| Command | Description | Usage |
|---------|-------------|-------|
| `server` | Start Nimhawk server (generates .xorkey file) | `docker run nimhawk server` |
| `compile` | Compile implants | `docker run nimhawk compile exe nim-debug` |
| `frontend` | Start only frontend dev server | `docker run nimhawk frontend` |
| `full` | Start both backend and frontend | `docker run nimhawk full` |
| `shell` | Interactive shell | `docker run -it nimhawk shell` |
| `help` | Show help message | `docker run nimhawk help` |

### Port Mapping

Configure ports to match your `config.toml` settings:

| Port | Service | Purpose | Configuration |
|------|---------|---------|---------------|
| `3000` | Frontend | React application | Fixed (Next.js dev server) |
| `9669` | Admin API | Backend API | `admin_api.port` in config.toml |
| `80` | Implant Listener | HTTP listener | `implants_server.port` + `type = "HTTP"` |
| `443` | Implant Listener | HTTPS listener | `implants_server.port` + `type = "HTTPS"` + SSL certs |

### SSL Configuration in Docker

To enable HTTPS for implant communications in Docker:

1. **Place SSL certificates in the container:**
```bash
# Mount certificates from host
docker run -it -p 3000:3000 -p 9669:9669 -p 443:443 \
  -v /path/to/certs:/certs \
  -v nimhawk-data:/nimhawk/server \
  nimhawk full
```

2. **Update config.toml:**
```toml
[implants_server]
type = "HTTPS"
port = 443
sslCertPath = "/certs/fullchain.pem"
sslKeyPath = "/certs/privkey.pem"
```

### Docker Examples

```bash
# Start full Nimhawk with persistent storage
docker run -it -p 3000:3000 -p 9669:9669 -p 80:80 -p 443:443 \
  -v nimhawk-data:/nimhawk/server \
  nimhawk full

# Compile implants only
docker run -it -v $(pwd)/output:/nimhawk/implant/bin \
  nimhawk compile all nim-release

# Interactive development
docker run -it -p 3000:3000 -p 9669:9669 -p 80:80 \
  -v $(pwd):/nimhawk \
  nimhawk shell
```

### How Docker Deployment Works

Docker simplifies deployment but the Python backend handles SSL natively based on `config.toml`:

1. **Frontend (Port 3000)**: Next.js development server serves the React application
2. **Admin API (Port 9669)**: Python Flask server handles admin/web interface API requests
3. **Implant Listener (Port 80/443)**: Python server handles implant communications with native SSL support
   - **HTTP Mode**: `type = "HTTP"` uses port 80
   - **HTTPS Mode**: `type = "HTTPS"` uses port 443 with certificates configured in `sslCertPath`/`sslKeyPath`
4. **SSL Termination**: Handled by the Python backend, not Docker

The Docker entrypoint script automatically:
- Installs frontend dependencies (`npm install`)
- Starts the Next.js dev server (`npm run dev`)  
- Starts the Python backend (`python3 nimhawk.py server`) which reads SSL config from `config.toml`
- Creates necessary directories and files

### Docker Compose

Create a `docker-compose.yml` for easier management:

```yaml
version: '3.8'
services:
  nimhawk:
    build: .
    ports:
      - "3000:3000"
      - "9669:9669"
      - "80:80"
      - "443:443"
    volumes:
      - nimhawk-data:/nimhawk/server
      - ./config.toml:/nimhawk/config.toml
    command: full
    stdin_open: true
    tty: true
    restart: unless-stopped

volumes:
  nimhawk-data:
```

Run with Docker Compose:
```bash
docker-compose up -d
```

## Production Deployment

### Prerequisites

#### System Requirements
- Linux server (Ubuntu 20.04+ recommended)
- 4GB RAM minimum, 8GB recommended
- 20GB disk space minimum
- Public IP address
- Domain name (optional but recommended)

#### Security Requirements
- SSL/TLS certificates (handled natively by Python backend)
- Firewall configuration
- Monitoring and logging

### Step-by-Step Production Setup

#### 1. Server Preparation
```bash
# Update system
sudo apt update && sudo apt upgrade -y

# Install required packages
sudo apt install -y python3 python3-pip python3-venv git nodejs npm nginx certbot

# Create nimhawk user
sudo useradd -m -s /bin/bash nimhawk
sudo usermod -aG sudo nimhawk

# Switch to nimhawk user
sudo su - nimhawk
```

#### 2. Application Setup
```bash
# Clone repository
git clone https://github.com/hdbreaker/nimhawk
cd nimhawk

# Configure environment
cp config.toml.example config.toml
# Edit config.toml for production settings

# Install Python dependencies
cd server
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt

# Install frontend dependencies
cd admin_web_ui
npm install
npm run build
```

#### 3. SSL Certificate Setup
```bash
# Using Let's Encrypt
sudo certbot certonly --standalone -d your-domain.com

# Copy certificates to Nimhawk directory
sudo cp /etc/letsencrypt/live/your-domain.com/fullchain.pem /home/nimhawk/nimhawk/
sudo cp /etc/letsencrypt/live/your-domain.com/privkey.pem /home/nimhawk/nimhawk/
sudo chown nimhawk:nimhawk /home/nimhawk/nimhawk/*.pem
```

#### 4. Configure SSL (Optional)

If you want to use HTTPS for implant communications, configure SSL in `config.toml`:

```toml
[implants_server]
type = "HTTPS"
port = 443
sslCertPath = "/etc/letsencrypt/live/your-domain.com/fullchain.pem"
sslKeyPath = "/etc/letsencrypt/live/your-domain.com/privkey.pem"
```

The Python backend handles SSL termination natively, eliminating the need for reverse proxies.

#### 4. Systemd Service Configuration

Create service file (`/etc/systemd/system/nimhawk.service`):

```ini
[Unit]
Description=Nimhawk C2 Server
After=network.target

[Service]
Type=simple
User=nimhawk
WorkingDirectory=/home/nimhawk/nimhawk
Environment=PATH=/home/nimhawk/nimhawk/server/venv/bin
ExecStart=/home/nimhawk/nimhawk/server/venv/bin/python /home/nimhawk/nimhawk/nimhawk.py server
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```

Enable and start the service:
```bash
sudo systemctl daemon-reload
sudo systemctl enable nimhawk
sudo systemctl start nimhawk
sudo systemctl status nimhawk
```

## Redirector Setup

Redirectors act as intermediaries between implants and the C2 server, providing additional operational security.

### Basic Redirector with socat

#### HTTP Redirector
```bash
# Install socat
sudo apt install socat

# Basic HTTP redirector
# Listens on port 80, redirects to C2 server
socat TCP4-LISTEN:80,fork TCP4:192.168.1.200:80

# With logging
socat TCP4-LISTEN:80,fork,reuseaddr TCP4:192.168.1.200:80 | tee -a /var/log/redirector.log
```

#### HTTPS Redirector
```bash
# Generate SSL certificate
openssl req -x509 -newkey rsa:4096 -keyout key.pem -out cert.pem -days 365 -nodes

# HTTPS redirector
socat OPENSSL-LISTEN:443,fork,reuseaddr,cert=cert.pem,key=key.pem,verify=0 \
  TCP4:192.168.1.200:443
```

### Multi-Redirector Chain

For enhanced security, chain multiple redirectors:

```
Implant -> Redirector1 -> Redirector2 -> C2 Server
```

#### Redirector1 Configuration (Public-facing)
```bash
# On Redirector1 (203.0.113.10)
# Accept all connections, redirect to Redirector2
socat TCP4-LISTEN:443,fork,reuseaddr TCP4:192.168.1.150:443 | tee -a /var/log/redirector1.log
```

#### Redirector2 Configuration (Internal)
```bash
# On Redirector2 (192.168.1.150)  
# Only accept from Redirector1, redirect to C2
iptables -A INPUT -p tcp -s 203.0.113.10 --dport 443 -j ACCEPT
iptables -A INPUT -p tcp --dport 443 -j DROP

socat TCP4-LISTEN:443,fork,reuseaddr TCP4:192.168.1.200:443 | tee -a /var/log/redirector2.log
```

#### C2 Server Configuration (Final destination)
```bash
# On C2 Server (192.168.1.200)
# Only accept from Redirector2
iptables -A INPUT -p tcp -s 192.168.1.150 --dport 443 -j ACCEPT
iptables -A INPUT -p tcp --dport 443 -j DROP
```

### Cloudflare Worker Redirector

For advanced setups, use Cloudflare Workers:

```javascript
addEventListener('fetch', event => {
  event.respondWith(handleRequest(event.request))
})

async function handleRequest(request) {
  // Forward to actual C2 server
  const targetUrl = 'https://your-c2-server.com'
  
  const modifiedRequest = new Request(targetUrl + request.url.substring(request.url.indexOf('/', 8)), {
    method: request.method,
    headers: request.headers,
    body: request.body
  })
  
  const response = await fetch(modifiedRequest)
  return response
}
```

### Redirector Monitoring

Monitor redirector health and traffic:

```bash
# Monitor active connections
watch -n 1 "netstat -an | grep :443"

# Monitor logs
tail -f /var/log/redirector.log

# Check redirector process
ps aux | grep socat
```

## Desktop Application Deployment

### Building Desktop Installers

#### Prerequisites
```bash
cd server/admin_web_ui
npm install electron electron-builder --save-dev
```

#### Build Commands
```bash
# Build for current platform
npm run electron-build

# Build for specific platforms
npm run electron-build:linux
npm run electron-build:mac
npm run electron-build:win
npm run electron-build:all
```

#### Generated Installers

| Platform | Format | Location |
|----------|--------|----------|
| Windows | `.exe` (NSIS installer) | `dist/` |
| macOS | `.dmg` (disk image), `.zip` | `dist/` |
| Linux | `.AppImage`, `.deb` | `dist/` |

### Remote Server Configuration for Desktop App

Configure desktop app to connect to remote server:

```bash
# Create environment file
cd server/admin_web_ui
cat > .env << 'EOF'
NEXT_PUBLIC_NIMHAWK_ADMIN_SERVER_IP=http://your-nimhawk-admin-api-server.com
NEXT_PUBLIC_NIMHAWK_ADMIN_SERVER_PORT=9669
NEXT_PUBLIC_NIMHAWK_IMPLANT_SERVER_IP=http://your-nimhawk-implants-api-server.com
NEXT_PUBLIC_NIMHAWK_IMPLANT_SERVER_PORT=80
EOF
```

### Distribution Strategy

#### Internal Distribution
1. Build installers for your platforms
2. Host on internal file server or repository
3. Distribute to team members
4. Provide configuration instructions

#### Secure Distribution
1. Code sign installers (for trusted execution)
2. Use checksums to verify integrity
3. Distribute through secure channels
4. Provide installation and configuration guide

## Distributed Deployment

### Frontend-Backend Separation

Deploy frontend and backend on separate servers for scalability and security.

#### Backend Server Setup
```bash
# Backend-only deployment
cd server
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt

# Start only the backend
python3 main.py Nimhawk
```

#### Frontend Server Setup
```bash
# Frontend-only deployment
cd server/admin_web_ui

# Configure backend endpoints
cat > .env << 'EOF'
NEXT_PUBLIC_NIMHAWK_ADMIN_SERVER_IP=http://your-nimhawk-admin-api-server.com
NEXT_PUBLIC_NIMHAWK_ADMIN_SERVER_PORT=9669
NEXT_PUBLIC_NIMHAWK_IMPLANT_SERVER_IP=http://your-nimhawk-implants-api-server.com
NEXT_PUBLIC_NIMHAWK_IMPLANT_SERVER_PORT=80
EOF

# Build and deploy
npm install
npm run build
npm start
```

#### Access Control
- Implement IP whitelisting for admin interface
- Use VPN for operator access
- Multi-factor authentication (if available)
- Regular access reviews

For additional troubleshooting, see [configuration guide](CONFIGURATION.md).