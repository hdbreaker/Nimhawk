# Nimhawk Multi-Platform Implant

A cross-platform implant for the Nimhawk C2 framework, supporting multiple architectures using only Nim standard library for maximum compatibility.

## 🎯 Supported Platforms

| Platform | Architecture | Status | Binary Name |
|----------|-------------|--------|-------------|
| **Linux** | x86_64 | ✅ Supported | `nimhawk_linux_x64` |
| **Linux** | ARM64 (aarch64) | ✅ Supported | `nimhawk_linux_arm64` |
| **Linux** | MIPS Little-Endian | ✅ Supported | `nimhawk_linux_mipsel` |
| **Linux** | ARM | ✅ Supported | `nimhawk_linux_arm` |
| **Darwin** | x86_64 (macOS) | ✅ Supported | `nimhawk_darwin` |

## 🚀 Quick Start

### Prerequisites

- **Nim compiler** >= 1.6.10
- **Make** (for build system)
- **Nimhawk C2 server** running

### Build All Platforms

```bash
cd multi_implant
make all
```

### Build Specific Platform

```bash
# Linux x86_64
make linux_x64

# Linux ARM64  
make linux_arm64

# Linux MIPS Little-Endian
make linux_mipsel

# Linux ARM
make linux_arm

# macOS
make darwin
```

### Custom XOR Key

```bash
make all XOR_KEY=987654321
```

## 📁 Project Structure

```
multi_implant/
├── main.nim                 # Entry point
├── multi_implant.nimble     # Package configuration
├── nim.cfg                  # Compiler settings
├── Makefile                 # Build system
├── README.md               # This file
├── bin/                    # Compiled binaries (created during build)
│
├── config/
│   └── configParser.nim    # Configuration parser
│
├── core/
│   ├── webClientListener.nim  # HTTP C2 communication
│   └── cmdParser.nim          # Command execution
│
├── modules/
│   ├── system/
│   │   ├── whoami.nim      # whoami command
│   │   ├── env.nim         # Environment variables
│   │   └── ps.nim          # Process list
│   │
│   └── filesystem/
│       ├── ls.nim          # Directory listing
│       ├── pwd.nim         # Current directory
│       └── cd.nim          # Change directory
│
└── util/
    ├── strenc.nim          # String encoding/obfuscation
    └── persistence.nim     # Cross-platform persistence
```

## 🛠️ Available Commands

The implant supports the following commands:

### System Information
- `whoami` - Get current username
- `env` - List environment variables  
- `ps` - List running processes

### Filesystem Operations
- `pwd` - Get current directory
- `ls [directory]` - List directory contents
- `cd <directory>` - Change directory

### Control Commands
- `sleep <seconds> [jitter]` - Set sleep time and jitter
- `kill` - Terminate implant

## 🐳 Testing with Docker

### Test Linux x86_64

```bash
# Build the implant
make linux_x64

# Test in Ubuntu container
docker run -it --rm \
  -v $(pwd)/bin:/tmp/nimhawk \
  ubuntu:20.04 \
  /tmp/nimhawk/nimhawk_linux_x64
```

### Test Linux ARM64

```bash
# Build ARM64 implant
make linux_arm64

# Test in ARM64 container (if Docker supports multi-arch)
docker run -it --rm \
  --platform linux/arm64 \
  -v $(pwd)/bin:/tmp/nimhawk \
  ubuntu:20.04 \
  /tmp/nimhawk/nimhawk_linux_arm64
```

### Test with Qemu (Multi-Architecture)

```bash
# Install qemu for multi-arch support
sudo apt-get install qemu-user-static

# Test MIPS implant
qemu-mipsel-static bin/nimhawk_linux_mipsel

# Test ARM implant  
qemu-arm-static bin/nimhawk_linux_arm
```

### Complete Docker Test Environment

Create a test script (`test_docker.sh`):

```bash
#!/bin/bash

echo "🐳 Testing Nimhawk Multi-Platform Implants with Docker"

# Build all implants
echo "📦 Building all implants..."
make all

# Test x86_64
echo "🧪 Testing Linux x86_64..."
docker run --rm -v $(pwd)/bin:/app ubuntu:20.04 /app/nimhawk_linux_x64 --help 2>/dev/null && echo "✅ x86_64 OK" || echo "❌ x86_64 Failed"

# Test ARM64 (if available)
echo "🧪 Testing Linux ARM64..."
docker run --rm --platform linux/arm64 -v $(pwd)/bin:/app ubuntu:20.04 /app/nimhawk_linux_arm64 --help 2>/dev/null && echo "✅ ARM64 OK" || echo "⚠️ ARM64 requires multi-arch Docker"

# Test with Alpine (smaller image)
echo "🧪 Testing with Alpine Linux..."
docker run --rm -v $(pwd)/bin:/app alpine:latest /app/nimhawk_linux_x64 --help 2>/dev/null && echo "✅ Alpine OK" || echo "❌ Alpine Failed"

echo "🎉 Testing complete!"
```

## 🔧 Configuration

The implant reads configuration from `../../config.toml` relative to the binary location. If the configuration file is not found, it uses built-in defaults.

### Sample Configuration

```toml
[implants_server]
hostname = ""
type = "HTTP"
port = 80
registerPath = "/api/register"
taskPath = "/api/task"
resultPath = "/api/result"
reconnectPath = "/api/reconnect"

[implant]
implantCallbackIp = "127.0.0.1"
killDate = "2025-12-31"
sleepTime = 10
sleepJitter = 20
userAgent = "Mozilla/5.0 (Linux; Nimhawk/1.4.0)"
httpAllowCommunicationKey = "DefaultKey123"
```

## 🔐 Security Features

### HTTP Protocol
- **Headers**: `X-Request-ID`, `X-Correlation-ID`, `X-Robots-Tag`, `User-Agent`
- **Authentication**: Pre-shared key authentication
- **Encryption**: Dual XOR key system (INITIAL + UNIQUE)
- **Encoding**: Base64 encoding for reliable transmission

### Operational Security
- **Configurable sleep/jitter** - Avoid pattern detection
- **Kill date support** - Time-boxed operations
- **Process persistence** - Cross-platform file-based persistence
- **Error resilience** - Graceful failure handling

## 🧪 Development & Testing

### Compilation Test

```bash
# Test compilation without building binaries
make test
```

### Debug Build

```bash
# Build with debug information and verbose output
make debug
```

### Adding New Commands

1. Create command module in `modules/` directory
2. Add include statement to `core/cmdParser.nim`
3. Add command case to `parseCmd` function

Example:
```nim
# modules/system/hostname.nim
proc hostname*(): string =
    try:
        return execProcess("hostname").strip()
    except:
        return "unknown"
```

## 🐛 Troubleshooting

### Build Issues

```bash
# Clean and rebuild
make clean
make all

# Check Nim installation
nim --version

# Test with debug output
make debug
```

### Runtime Issues

```bash
# Run with verbose output (if compiled with -d:verbose)
./bin/nimhawk_linux_x64

# Check configuration
cat ../../config.toml

# Test network connectivity
curl -I http://your-c2-server.com/api/register
```

### Architecture-Specific Issues

```bash
# Check binary architecture
file bin/nimhawk_linux_x64
file bin/nimhawk_linux_arm64

# Test with qemu if cross-compiling
qemu-aarch64-static bin/nimhawk_linux_arm64
```

## 📚 Protocol Documentation

The implant follows the Nimhawk C2 protocol:

### Registration Flow
1. **GET** `/api/register` - Initialize implant ID and get UNIQUE_XOR_KEY
2. **POST** `/api/register` - Send system information (encrypted)

### Command Flow  
1. **GET** `/api/task` - Poll for commands
2. **POST** `/api/result` - Submit command results (encrypted)

### Reconnection Flow
1. **OPTIONS** `/api/reconnect` - Recover UNIQUE_XOR_KEY after restart

## 🔄 Continuous Integration

### GitHub Actions Example

```yaml
name: Multi-Platform Build

on: [push, pull_request]

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v2
    - name: Install Nim
      run: |
        wget https://nim-lang.org/choosenim/init.sh
        sh init.sh -y
        echo ~/.nimble/bin >> $GITHUB_PATH
    - name: Build all platforms
      run: |
        cd multi_implant
        make test
        make all
    - name: Upload artifacts
      uses: actions/upload-artifact@v2
      with:
        name: nimhawk-implants
        path: multi_implant/bin/
```

## 📄 License

MIT License - see main project for details.

## 🤝 Contributing

1. Fork the repository
2. Create feature branch (`git checkout -b feature/new-command`)
3. Add your command module
4. Test with `make test`
5. Submit pull request

## 🎯 Roadmap

- [ ] **Network commands**: `curl`, `wget`, `upload`, `download`
- [ ] **Advanced persistence**: Systemd services, cron jobs
- [ ] **Process injection**: Linux-specific injection techniques  
- [ ] **Credential harvesting**: SSH keys, browser passwords
- [ ] **Network discovery**: Port scanning, service enumeration
- [ ] **Container awareness**: Docker/Kubernetes detection
- [ ] **Memory-only execution**: Fileless operation modes

---

**Made with ❤️ for the Nimhawk project** 