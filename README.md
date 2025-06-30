<div align="center">
  <img src="docs/images/nimhawk.png" height="150">

  <h1>Nimhawk - A Powerful, Modular, Lightweight and Efficient Command & Control Framework</h1>

[![PRs Welcome](https://img.shields.io/badge/Contributions-Welcome-brightgreen.svg)](DEVELOPERS.md#contributing)
[![Platform](https://img.shields.io/badge/Implant-Windows%20x64-blue.svg)](https://github.com/hdbreaker/nimhawk)
[![License](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Version](https://img.shields.io/badge/Version-1.4.0-red.svg)](https://github.com/hdbreaker/nimhawk/releases)
[![Buy Me A Coffee](https://img.shields.io/badge/Buy%20Me%20A%20Coffee-Support-orange.svg)](https://buymeacoffee.com/hdbreaker9s)
</div>

---

## ⚠️ Disclaimer

This project is intended **solely for educational and authorized red teaming purposes**.

Nimhawk was created as a research framework for simulating command-and-control operations in lab environments, helping professionals understand advanced attacker techniques and improve defensive posture.

You are **responsible for using this tool only in systems you own or have explicit permission to test**. Unauthorized access, use, or distribution of malware is illegal and unethical.

The author assumes **no responsibility** for any misuse of this code.

By using this software, you agree to comply with all applicable laws and regulations in your jurisdiction.

> 📚 **For comprehensive legal information, please read [LEGAL.md](LEGAL.md)**

## 🎓 Educational Focus

### Research Applications
- **Malware Analysis**: Study C2 communication patterns in controlled environments
- **Detection Development**: Create and test security rules for SOC teams  
- **Academic Research**: Support cybersecurity coursework and thesis projects
- **Red Team Training**: Practice authorized adversary simulation techniques
- **Blue Team Defense**: Understand attacker methodologies to improve detection

### Learning Objectives
This framework helps security professionals understand:
- Advanced Persistent Threat (APT) tactics and techniques
- Command and control communication protocols
- Evasion techniques and their detection
- Incident response and forensic analysis
- Network security monitoring and detection

## 🛡️ Responsible Use Guidelines

### ✅ Authorized Use Cases
- **Laboratory Testing**: Isolated network environments for research
- **Academic Institutions**: Cybersecurity education and coursework
- **Security Training**: Authorized corporate security training programs
- **Penetration Testing**: With proper written authorization and scope
- **Research Projects**: Academic or industry cybersecurity research

### 📋 Before You Begin
1. **Obtain Written Permission**: Ensure you have explicit authorization
2. **Document Your Scope**: Clearly define testing boundaries and objectives
3. **Use Isolated Networks**: Never test on production systems without authorization
4. **Follow Legal Requirements**: Comply with all applicable laws and regulations
5. **Practice Responsible Disclosure**: Report findings through proper channels

### 🚫 Strictly Prohibited
- Unauthorized access to any computer system
- Testing without explicit written permission
- Malicious use or criminal activities
- Distribution of compiled implants without proper context
- Any use that violates local or international laws

---

> ⚠️ **LEGAL WARNING**: This tool is designed exclusively for authorized security professionals, legitimate penetration testing, and academic research. Unauthorized use is illegal and may result in criminal prosecution.

> 🛡️ **ETHICAL USE ONLY**: By using this software, you agree to use it only for legal purposes with proper authorization.

> 🚧 **Development Status**: Nimhawk is currently in active development. Core functionality is working, but some features are still experimental. The implant only supports Windows x64 platforms. Contributions and feedback are highly welcomed!

## Table of Contents

### 🚀 Quick Start
- [5-Minute Setup](#5-minute-setup)
- [What is Nimhawk?](#what-is-nimhawk)
- [Key Features](#key-features)

### 📚 Complete Documentation
- [📦 Installation Guide](INSTALLATION.md) - Detailed installation instructions for all platforms
- [⚙️ Configuration Reference](CONFIGURATION.md) - Complete configuration options and examples
- [🚀 Deployment Guide](DEPLOYMENT.md) - Production deployment, Docker, and redirector setup
- [🏗️ Architecture Overview](ARCHITECTURE.md) - Technical architecture and design patterns
- [👨‍💻 Developer Guide](DEVELOPERS.md) - Development, contribution guidelines, and API documentation
- [📋 Version Management](VERSION_MANAGEMENT.md) - Version control and update procedures
- [🔗 Relay System Guide](RELAY_SYSTEM.md) - SONET relay messaging system documentation

### ⚖️ Legal and Ethical Guidelines
- [📜 Legal Notice](LEGAL.md) - Comprehensive legal disclaimer and terms of use
- [🤝 Code of Conduct](CODE_OF_CONDUCT.md) - Community standards and ethical guidelines

### 🛠️ Quick Reference
- [System Requirements](#system-requirements)
- [Available Commands](#available-commands)
- [Troubleshooting](#troubleshooting)
- [FAQ](#faq)

### 📖 Project Information
- [Acknowledgments](#acknowledgments)
- [Community](#community)
- [Contributing](#contributing)
- [Disclaimer](#disclaimer)

## 🚀 5-Minute Setup

### Prerequisites Check
```bash
# Verify Python version
python3 --version  # Should be 3.8+

# Verify Nim installation
nim --version       # Should be latest stable

# Verify Git
git --version
```

### Quick Installation
```bash
# 1. Clone and setup
git clone https://github.com/hdbreaker/nimhawk
cd nimhawk
cp config.toml.example config.toml

# 2. Install server dependencies
cd server
python3 -m venv venv
source venv/bin/activate  # Linux/macOS
pip install -r requirements.txt

# 3. Install frontend dependencies
cd admin_web_ui
npm install

# 4. Start services (2 terminals)
# Terminal 1: Backend
python3 ../../nimhawk.py server

# Terminal 2: Frontend
npm run dev
```

### Access Interface
- Open browser: `http://localhost:3000`
- Default credentials: `admin@nimhawk.com` / `P4ssw0rd123$`
- **⚠️ Change default credentials immediately!**

> 📚 For detailed installation instructions, see [INSTALLATION.md](INSTALLATION.md)

## What is Nimhawk?

Nimhawk is an advanced command and control (C2) framework that builds upon the exceptional foundation laid by [Cas van Cooten](https://github.com/chvancooten) ([@chvancooten](https://twitter.com/chvancooten)) with his [NimPlant](https://github.com/chvancooten/NimPlant) project.

### Key Improvements Over NimPlant
- **🏗️ Modular Architecture**: Designed for easier contributions and extensions
- **🔐 Enhanced Security**: Dual authentication system and improved evasion capabilities
- **🌐 Modern Web Interface**: Complete renovation with modern authentication
- **📊 Better Data Handling**: Improved data processing and command systems
- **📚 Comprehensive Documentation**: Practical deployment and usage focused
- **👥 Multi-User Support**: Role-based access control
- **🗂️ Workspace Management**: Better operational organization
- **📡 Real-Time Monitoring**: Visual implant status indicators
- **📁 File Transfer System**: Enhanced with preview capabilities
- **🔄 Robust Error Handling**: Improved reconnection mechanisms
- **🛠️ Integrated Build System**: Web-based compilation
- **🐳 Flexible Deployment**: Including Docker support

## Key Features

### 🎯 Core Capabilities
- ✨ **Modular Architecture**: Designed for easy expansion and contribution
- 🛡️ **Enhanced Implant**: Reduced detection signatures with advanced evasion
- 🌐 **Advanced Web Interface**: Intuitive dashboard with real-time updates
- 🔧 **Web Compilation**: Generate implants directly from dashboard
- 🖥️ **Desktop Application**: Cross-platform Electron-based standalone app

### 🔐 Security Features
- 🔐 **Dual Authentication**: Web UI and implant-server authentication systems
- 📊 **Optimized Storage**: Efficient data handling and compression
- 🔍 **Enhanced Debugging**: Improved error tracking and logging
- 📡 **Multi-Status Support**: Real-time implant monitoring with visual indicators
- 🔑 **XOR Encryption**: Dual-key encryption system for secure communications

### 🚀 Recent Improvements
- **Enhanced Check-in System**: Optimized implant tracking separated from command history
- **Refined Data Transfer**: More accurate measurement of data transferred
- **UI Improvements**: Enhanced implant details display with real-time metrics
- **Improved Reconnection**: Better registry cleanup and error handling
- **Inactive Implant Management**: Safe database cleanup procedures
- **CRL Self-Hosting**: Multiple .NET assembly execution without breaking implants
- **DInvoke Integration**: In-memory DInvoke for improved OPSEC
- **PowerShell Support**: Fixed and enhanced PowerShell command execution
- **Encrypted Reverse Shell**: XOR-encrypted reverse shell with enhanced OPSEC
- **Relay Messaging System (SONET)**: Modular relay system for chained agent communication

## System Requirements

### 📋 Minimum Requirements
| Component | Server | Implant Target |
|-----------|---------|----------------|
| **Operating System** | Linux/macOS/Windows | Windows x64 |
| **RAM** | 2GB minimum | 50MB available |
| **Disk Space** | 1GB free | 10MB free |
| **Python** | 3.8+ | N/A |
| **Nim Compiler** | Latest stable | N/A |
| **Network** | Internet access | Outbound connectivity |

### 🔧 Development Requirements
| Tool | Version | Purpose |
|------|---------|---------|
| **Git** | Latest | Source code management |
| **Node.js** | 16+ | Frontend development |
| **MinGW-w64** | Latest | Cross-compilation (Linux/macOS to Windows) |

### Platform Compatibility

| Platform | Server Support | Implant Support | Notes |
|----------|---------------|-----------------|--------|
| **Ubuntu 20.04+** | ✅ Fully Supported | N/A | Recommended for production |
| **Debian 11+** | ✅ Fully Supported | N/A | Tested and working |
| **Kali Linux** | ✅ Fully Supported | N/A | Optimized for pentesting |
| **macOS 11+** | ✅ Fully Supported | N/A | Intel and Apple Silicon |
| **Windows 10+** | ⚠️ Limited Support | ✅ Primary Target | May require additional config |
| **Windows 7 SP1+** | N/A | ✅ Supported | Legacy OS support |
| **Windows Server 2012 R2+** | N/A | ✅ Working | Limited testing |
| **Linux** | N/A | ❌ Planned | Future release |
| **macOS** | N/A | ❌ Planned | Future release |

> 📚 For detailed system requirements and installation instructions, see [INSTALLATION.md](INSTALLATION.md)

## Available Commands

### System Information
- `whoami` - Display current user information
- `hostname` - Display system hostname  
- `ps` - List running processes
- `env` - Show environment variables
- `getav` - Get antivirus information
- `getdom` - Get domain information

### File System Operations
- `ls [directory]` - List directory contents
- `cd [directory]` - Change current directory
- `pwd` - Print working directory
- `cat [file]` - Display file contents
- `rm [file]` - Remove file
- `mkdir [directory]` - Create directory
- `cp [source] [destination]` - Copy file
- `mv [source] [destination]` - Move or rename file

### Network Operations
- `curl [url]` - Make HTTP request
- `download [file]` - Download file from target
- `upload [file]` - Upload file to target
- `wget [url] [destination]` - Download file from URL

### Execution Commands
- `run [command]` - Execute command and capture output

### Risky Commands (Available in Risky Mode)
- `execute-assembly [file]` - Execute .NET assembly in memory
- `inline-execute [file]` - Execute raw shellcode in memory
- `powershell [command]` - Execute PowerShell command
- `shell [command]` - Execute shell command (cmd.exe)
- `shinject [pid] [file]` - Inject shellcode into process

### Control Commands
- `sleep [seconds] [jitter]` - Set sleep time and jitter
- `checkin` - Force check-in with server
- `kill` - Terminate implant

### Relay Commands
- `relay [port]` - Start relay server for downstream agents
- `connect relay://IP:PORT` - Connect to upstream relay

> 📚 For detailed command usage and examples, see [DEVELOPERS.md](DEVELOPERS.md#available-commands)

## Troubleshooting

### Common Issues

#### Connection Refused Error
**Symptom**: Implant cannot connect to server  
**Solutions**: 
1. Verify server is running: `python3 nimhawk.py server`
2. Check firewall configuration
3. Validate `config.toml` settings
4. Test connectivity: `telnet <server_ip> <port>`

#### Permission Denied During Compilation
**Symptom**: Permission errors during build process  
**Solutions**: 
1. Check directory permissions: `chmod -R 755 nimhawk/`
2. Run with appropriate privileges
3. Verify Nim installation: `nim --version`
4. Check MinGW-w64 installation (for cross-compilation)

#### Frontend Not Loading
**Symptom**: Web interface shows errors or won't load  
**Solutions**:
1. Verify Node.js version: `node --version` (should be 16+)
2. Clear npm cache: `npm cache clean --force`
3. Reinstall dependencies: `rm -rf node_modules && npm install`
4. Check port availability: `netstat -an | grep 3000`

#### Implant Not Connecting
**Symptom**: Compiled implant doesn't appear in dashboard  
**Solutions**:
1. Check `config.toml` listener configuration
2. Verify network connectivity from target
3. Check Windows Defender/Antivirus logs
4. Validate HTTP communication key
5. Review server logs for connection attempts

> 📚 For comprehensive troubleshooting, see [INSTALLATION.md](INSTALLATION.md#troubleshooting)

## FAQ

### General Questions

**Q: What is Nimhawk?**  
A: Nimhawk is a Command & Control (C2) framework designed for red team operations, featuring a Python backend server and implants written in the Nim programming language.

**Q: How is Nimhawk different from other C2 frameworks?**  
A: Nimhawk focuses on modularity, ease of contribution, and comprehensive documentation. It's designed for learning and research, with a modern web interface and extensive evasion capabilities.

**Q: Is Nimhawk free to use?**  
A: Yes, Nimhawk is open-source and free to use under the MIT license. However, it's designed for legitimate security testing with proper authorization only.

### Technical Questions

**Q: What platforms does the implant support?**  
A: Currently, Nimhawk implants only work on Windows x64 environments (Windows 7 SP1 and newer). Linux and macOS support is planned for future releases.

**Q: Can I compile implants on Mac/Linux?**  
A: Yes, you can cross-compile Windows implants from Linux or macOS using the MinGW toolchain. See our [Installation Guide](INSTALLATION.md) for details.

**Q: Does Nimhawk support HTTPS communications?**  
A: Yes, Nimhawk supports both HTTP and HTTPS communications. Configure SSL certificates in the `config.toml` file for HTTPS.

### Operational Questions

**Q: How do I create and deploy an implant?**  
A: 1) Configure your `config.toml` file, 2) Use the web interface "Compile Implants" button, 3) Deploy the generated implant on your target system, 4) Monitor connections in the dashboard.

**Q: How can I contribute to Nimhawk?**  
A: Contributions are welcome! Check our [Developer Guide](DEVELOPERS.md) for guidelines on contributing to the project.

> 📚 For more detailed FAQ, see individual documentation files

## Community

> 🤝 **Community**: Hey! If you're into Malware Dev, Hacking, Exploit writing or just a tech nerd like me - hit me up! Always looking for new hacker friends to collaborate, share ideas and maybe grab a beer. No fancy resumes needed.

> 🤝 **Code Contribution**: We're looking forward to developers building a Linux agent for Nimhawk. The developer's documentation, especially the section 'How to develop your own Implant or extend Implant functionality,' should be sufficient for the task.

### Ways to Contribute
- 🐛 **Bug Reports**: Found an issue? Report it!
- 💡 **Feature Requests**: Have an idea? Share it!
- 🔧 **Code Contributions**: Submit pull requests
- 📝 **Documentation**: Help improve our docs
- 🧪 **Testing**: Test on different platforms

> 📚 For detailed contribution guidelines, see [DEVELOPERS.md](DEVELOPERS.md#contributing)

## Contributing

We welcome contributions from the community! Here's how you can help:

1. **Fork the repository**
2. **Create a feature branch**
3. **Make your changes**
4. **Test thoroughly**
5. **Submit a pull request**

> 📚 See [DEVELOPERS.md](DEVELOPERS.md) for detailed development setup and contribution guidelines.

## Acknowledgments

Special thanks to [Cas van Cooten](https://github.com/chvancooten) for creating NimPlant, the project that served as the fundamental basis for Nimhawk. You can find him on Twitter [@chvancooten](https://twitter.com/chvancooten).

We would also like to express our gratitude to:

- **[MalDev Academy](https://maldevacademy.com/)** for their exceptional educational resources on malware development techniques
- **[VX-Underground](https://vx-underground.org/)** for maintaining the largest collection of malware source code and research papers
- **The Nim Community** for their excellent programming language and support
- **All Contributors** who have helped improve this project

## Disclaimer

### Legal Notice

This tool should only be used in strictly controlled environments with proper authorization. The authors and contributors of Nimhawk assume no liability and are not responsible for any misuse or damage caused by this program. Users are responsible for ensuring compliance with local, state, and federal laws and regulations.

### Intended Use

Nimhawk is designed for and intended to be used by:
- Information Security Professionals
- Red Team Operators
- Security Researchers
- Defensive Security Specialists
- Malware Development Students

### Terms of Use

By using Nimhawk, you agree that:
1. You will only use it for legal purposes
2. You have proper authorization for testing
3. You will not use it for unauthorized access or exploitation
4. You understand the risks and consequences of misuse

### Educational Purpose

The primary purpose of this framework is to facilitate technical research into malware development and operations, enabling the improvement of defensive strategies and detection mechanisms.

---

<div align="center">

**Made with ❤️ by the Nimhawk Team**

[GitHub](https://github.com/hdbreaker/nimhawk) • [Installation](INSTALLATION.md) • [Configuration](CONFIGURATION.md) • [Deployment](DEPLOYMENT.md) • [Architecture](ARCHITECTURE.md) • [Development](DEVELOPERS.md)

[![Buy Me A Coffee](https://www.buymeacoffee.com/assets/img/custom_images/orange_img.png)](https://buymeacoffee.com/hdbreaker9s)

</div>
