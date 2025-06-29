# Installation Guide

This guide provides detailed instructions for installing and setting up Nimhawk on various platforms.

## Table of Contents

- [Prerequisites](#prerequisites)
- [Quick Installation](#quick-installation)
- [Detailed Installation](#detailed-installation)
- [Cross-Compilation Setup](#cross-compilation-setup)
- [Desktop Application Setup](#desktop-application-setup)
- [Verification](#verification)
- [Troubleshooting](#troubleshooting)

## Prerequisites

### System Requirements

#### Server Requirements
| Component | Requirement | Notes |
|-----------|-------------|--------|
| Python | 3.8+ | Required for backend |
| RAM | 2GB+ | Minimum recommended |
| Disk | 1GB+ | For database and logs |
| OS | Any modern OS | Linux recommended |

#### Development Requirements
| Tool | Version | Purpose |
|------|---------|---------|
| Git | Latest | Source code management |
| Node.js | 16+ | Frontend development |
| Nim | Latest stable | Implant compilation |
| MinGW-w64 | Latest | Cross-compilation (Linux/macOS) |

### Platform-Specific Prerequisites

#### Linux (Ubuntu/Debian)
```bash
# Update package lists
sudo apt update

# Install required packages
sudo apt install -y python3 python3-pip python3-venv git nodejs npm

# Install MinGW for cross-compilation
sudo apt install -y mingw-w64

# Install Nim
curl https://nim-lang.org/choosenim/init.sh -sSf | sh
```

#### macOS
```bash
# Install Homebrew if not already installed
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Install required packages
brew install python3 git node npm mingw-w64

# Install Nim
curl https://nim-lang.org/choosenim/init.sh -sSf | sh
```

#### Windows
```powershell
# Install Chocolatey if not already installed
Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))

# Install required packages
choco install python3 git nodejs nim

# Verify installations
python --version
git --version
node --version
nim --version
```

## Quick Installation

### 1. Clone Repository
```bash
git clone https://github.com/hdbreaker/nimhawk
cd nimhawk
```

### 2. Configure Environment
```bash
# Copy example configuration
cp config.toml.example config.toml

# Edit configuration (see CONFIGURATION.md for details)
nano config.toml  # or your preferred editor
```

### 3. Install Dependencies

#### Python Backend
```bash
cd server
python3 -m venv venv

# Activate virtual environment
source venv/bin/activate  # Linux/macOS
# .\venv\Scripts\activate  # Windows

# Install dependencies
pip install -r requirements.txt
```

#### Nim Implant
```bash
cd ../implant

# Install dependencies only
nimble install --depsOnly

# Note: If you encounter package errors, see Troubleshooting section
```

#### Frontend
```bash
cd ../server/admin_web_ui
npm install
```

### 4. Start Services
```bash
# Terminal 1: Start backend
cd ../../
python3 nimhawk.py server

# Terminal 2: Start frontend
cd server/admin_web_ui
npm run dev
```

## Detailed Installation

### Installing Nim and Nimble

#### Using choosenim (Recommended)
```bash
# Install choosenim
curl https://nim-lang.org/choosenim/init.sh -sSf | sh

# Restart shell or source the profile
source ~/.profile

# Install latest stable Nim
choosenim stable

# Verify installation
nim --version
nimble --version
```

#### Manual Installation
```bash
# Download Nim source
git clone https://github.com/nim-lang/Nim.git
cd Nim

# Build Nim
git clone --depth 1 https://github.com/nim-lang/csources.git
cd csources && sh build.sh
cd ..
./bin/nim c koch
./koch boot -d:release
./koch nimble

# Add to PATH
echo 'export PATH="$HOME/Nim/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

### Python Environment Setup

#### Virtual Environment (Recommended)
```bash
cd server

# Create virtual environment
python3 -m venv venv

# Activate virtual environment
source venv/bin/activate  # Linux/macOS
# .\venv\Scripts\activate  # Windows

# Upgrade pip
pip install --upgrade pip

# Install dependencies
pip install -r requirements.txt
```

#### System-wide Installation (Not Recommended)
```bash
cd server
pip3 install -r requirements.txt
```

### Frontend Dependencies

#### Install Node.js and npm
```bash
# Verify Node.js version (should be 16+)
node --version
npm --version

# If version is too old, install newer version
# Using Node Version Manager (nvm)
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash
source ~/.bashrc
nvm install 18
nvm use 18
```

#### Install Frontend Dependencies
```bash
cd server/admin_web_ui

# Install dependencies
npm install

# Optional: Install global dependencies
npm install -g next
```

## Cross-Compilation Setup

### For Linux/macOS to Windows

#### Install MinGW-w64
```bash
# Ubuntu/Debian
sudo apt install mingw-w64

# macOS
brew install mingw-w64

# Verify installation
x86_64-w64-mingw32-gcc --version
```

#### Configure nim.cfg
```bash
cd implant

# Create or edit nim.cfg
cat > nim.cfg << 'EOF'
# Target OS
os = windows

# 64-bit Windows compilation settings
amd64.windows.gcc.path = "/usr/bin"
amd64.windows.gcc.exe = "x86_64-w64-mingw32-gcc"
amd64.windows.gcc.linkerexe = "x86_64-w64-mingw32-gcc"

# Assembly and linker options
--passC:"-masm=intel"
--passL:"-Wl,--image-base"
--passL:"-Wl,0x400000"
EOF
```

#### Test Cross-Compilation
```bash
# Compile a simple test
nim c --cpu:amd64 --os:windows test.nim

# Should produce test.exe
file test.exe
```

### Troubleshooting Cross-Compilation

#### Common Issues

**MinGW not found**
```bash
# Find MinGW installation
which x86_64-w64-mingw32-gcc

# Update nim.cfg with correct path
# Example for macOS with Homebrew
amd64.windows.gcc.path = "/opt/homebrew/bin"
```

**Compilation errors**
```bash
# Verify MinGW installation
x86_64-w64-mingw32-gcc --version

# Check Nim configuration
nim --help
```

## Desktop Application Setup

### Installing Electron Dependencies
```bash
cd server/admin_web_ui

# Install Electron and related dependencies
npm install electron electron-builder --save-dev

# Verify installation
npx electron --version
```

### Development Mode
```bash
# Terminal 1: Start backend
python3 server/main.py Nimhawk

# Terminal 2: Start Electron app
cd server/admin_web_ui
npm run electron-dev
```

### Building Desktop Installers
```bash
cd server/admin_web_ui

# Build for current platform
npm run electron-build

# Build for specific platforms
npm run electron-build:linux
npm run electron-build:mac
npm run electron-build:win
npm run electron-build:all
```

### Remote Server Configuration
```bash
cd server/admin_web_ui

# Create environment configuration
cat > .env << 'EOF'
NEXT_PUBLIC_NIMHAWK_ADMIN_SERVER_IP=http://your-nimhawk-admin-api-server.com
NEXT_PUBLIC_NIMHAWK_ADMIN_SERVER_PORT=9669
NEXT_PUBLIC_NIMHAWK_IMPLANT_SERVER_IP=http://your-nimhawk-implants-api-server.com
NEXT_PUBLIC_NIMHAWK_IMPLANT_SERVER_PORT=80
EOF
```

## Verification

### Test Installation
```bash
# Test Python backend
cd server
python3 -c "import flask; print('Flask OK')"
python3 -c "import sqlite3; print('SQLite OK')"

# Test Nim compilation
cd ../implant
nim --version
nimble --version

# Test frontend
cd ../server/admin_web_ui
npm test
```

### Compile Test Implant
```bash
# Compile test implant
python3 nimhawk.py compile exe nim-debug

# Check generated files
ls -la implant/bin/
```

### Start and Test Services
```bash
# Start backend (Terminal 1)
python3 nimhawk.py server

# Start frontend (Terminal 2)
cd server/admin_web_ui
npm run dev

# Test web interface
curl http://localhost:3000
curl http://localhost:9669/api/health
```

## Troubleshooting

### Common Installation Issues

#### Python Issues
```bash
# Python version check
python3 --version

# If Python 3.8+ not available
sudo apt install python3.9 python3.9-venv python3.9-pip

# Virtual environment issues
rm -rf venv
python3 -m venv venv
source venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt
```

#### Nim Issues
```bash
# Nim not found
echo $PATH
which nim

# Reinstall Nim
rm -rf ~/.nimble ~/.choosenim
curl https://nim-lang.org/choosenim/init.sh -sSf | sh
```

#### Compilation Issues

**Error: cannot open file: nimvoke/syscalls**
```bash
# This error occurs when nimvoke dependency is missing
cd implant
nimble install --depsOnly

# If the error persists, install nimvoke manually
nimble install nimvoke
```

**Error: cannot find package registry/dynlib/unicode**
```bash
# These are standard library modules that should NOT be in implant.nimble
# The issue is already fixed in the current version, but if you encounter it:

# 1. Check your implant.nimble file - it should only contain:
# requires "nim >= 1.6.10"
# requires "nimcrypto >= 0.6.0"
# requires "parsetoml >= 0.7.1"
# requires "pixie >= 5.0.6"
# requires "ptr_math >= 0.3.0"
# requires "puppy >= 2.1.0"
# requires "winim >= 3.9.2"
# requires "zippy >= 0.10.4"
# requires "nimvoke >= 0.1.0"

# 2. Remove any standard library references (registry, dynlib, unicode, etc.)
# 3. Reinstall dependencies
nimble install --depsOnly
```

**Cross-compilation errors**
```bash
# Use the correct compilation command
cd implant
nim c -d:mingw NimHawk.nim

# If you get linker errors, ensure MinGW is properly installed
sudo apt install mingw-w64  # Linux
brew install mingw-w64      # macOS

# For lld linker issues
sudo apt install lld
```

#### Node.js Issues
```bash
# Node version too old
node --version

# Install newer version
nvm install 18
nvm use 18
nvm alias default 18
```

#### Permission Issues
```bash
# Fix directory permissions
chmod -R 755 nimhawk/

# Fix npm permissions
sudo chown -R $(whoami) ~/.npm
```

### Platform-Specific Issues

#### macOS Apple Silicon
```bash
# Compile Nim from source for Apple Silicon
git clone https://github.com/nim-lang/Nim.git
cd Nim
git clone --depth 1 https://github.com/nim-lang/csources.git
cd csources && sh build.sh
cd ..
./bin/nim c koch
./koch boot -d:release
```

#### Linux Missing Dependencies
```bash
# Ubuntu/Debian
sudo apt install build-essential libssl-dev libffi-dev

# CentOS/RHEL
sudo yum groupinstall "Development Tools"
sudo yum install openssl-devel libffi-devel
```

#### Windows Path Issues
```powershell
# Add to PATH in PowerShell
$env:PATH += ";C:\path\to\nim\bin"

# Make permanent
[Environment]::SetEnvironmentVariable("PATH", $env:PATH + ";C:\path\to\nim\bin", "User")
```

### Getting Help

If you encounter issues not covered here:
1. Check the [main README](README.md) troubleshooting section
2. Review the [GitHub issues](https://github.com/hdbreaker/nimhawk/issues)
3. Join our community discussions
4. Create a new issue with detailed information

## Next Steps

After successful installation:
1. Review the [Configuration Guide](CONFIGURATION.md)
2. Check the [Deployment Guide](DEPLOYMENT.md) for production setups
3. Explore the [Architecture Overview](ARCHITECTURE.md)
4. Start with the [Quick Start Guide](README.md#5-minute-setup) 