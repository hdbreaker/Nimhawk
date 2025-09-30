# Nimhawk C2 - Quick Start Guide

## 🚀 First Time Setup (Replit)

### 1. Run Automated Setup

```bash
chmod +x setup.sh
./setup.sh
```

This installs everything you need: Nim, Python dependencies, and configures your environment.

### 2. Backend is Already Running

The backend starts automatically via the configured workflow:
- **Admin API**: https://YOUR-REPLIT-DOMAIN (check your browser)
- **Default Login**: admin@nimhawk.com / P4ssw0rd123$

⚠️ **IMPORTANT**: Change the default password in `config.toml` immediately!

## 🔨 Compile Your First Implant

### Multi-Platform Implant (Linux/macOS)

```bash
cd multi_implant
export PATH="$HOME/.nimble/bin:$PATH"

# Compile for Linux x64
make linux_x64

# Or compile all platforms
make all
```

Binaries will be in `multi_implant/bin/`

### Windows Implant

For Windows implant compilation, see `INSTALLATION.md` - requires additional dependencies.

## 📡 Testing Implant Connection

1. **Copy the compiled implant** to your test system
2. **Run it**: `./multi_implant/bin/nimhawk_linux_x64`
3. **Check the Admin API** - Your implant should appear in the dashboard

## 🔧 Configuration

### Key Settings in config.toml

```toml
[admin_api]
port = 5000  # Required for Replit

[implants_server]
port = 8080  # Internal listener

[implant]
implantCallbackIp = "YOUR-REPLIT-DOMAIN"  # Auto-configured by setup.sh
```

## 📚 Next Steps

1. **Explore the Admin API**: https://YOUR-REPLIT-DOMAIN/api/server
2. **Read full docs**: See `INSTALLATION.md` and `CONFIGURATION.md`
3. **Build frontend** (optional): `cd server/admin_web_ui && npm install && npm run dev`

## 🐳 Using Docker Instead

```bash
# Build
docker build -t nimhawk .

# Run
docker run -p 5000:5000 -p 8080:8080 nimhawk server
```

## ❓ Troubleshooting

### Backend not running?
```bash
cd server
python main.py
```

### Nim not found?
```bash
export PATH="$HOME/.nimble/bin:$PATH"
nim --version
```

### Implant won't compile?
```bash
nimble install -y nimcrypto parsetoml puppy
```

## 🔐 Security Reminder

This is a penetration testing tool. Use only on systems you own or have explicit authorization to test.

- Change default credentials immediately
- Use HTTPS in production
- Keep .xorkey file secure
- Review config.toml settings

---

**Ready to dive deeper?** Check out the full documentation:
- `INSTALLATION.md` - Detailed installation guide
- `CONFIGURATION.md` - All configuration options
- `ARCHITECTURE.md` - System architecture details
