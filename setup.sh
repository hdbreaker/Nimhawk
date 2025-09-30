#!/bin/bash

set -e

echo "================================================"
echo "  Nimhawk C2 Framework - Environment Setup"
echo "================================================"
echo ""

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

# Detect operating system
detect_os() {
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        OS="linux"
        info "Detected Linux"
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        OS="macos"
        info "Detected macOS"
    else
        warn "Unsupported OS: $OSTYPE"
        OS="unknown"
    fi
}

# Check if running in Replit
is_replit() {
    if [ -n "$REPL_ID" ] || [ -n "$REPLIT_DEV_DOMAIN" ]; then
        return 0
    else
        return 1
    fi
}

# Install Python dependencies
install_python_deps() {
    info "Installing Python dependencies..."
    
    if [ ! -f "server/requirements.txt" ]; then
        error "server/requirements.txt not found!"
    fi
    
    cd server
    pip install --upgrade pip
    pip install -r requirements.txt
    cd ..
    
    info "✓ Python dependencies installed"
}

# Install Nim compiler
install_nim() {
    if command -v nim &> /dev/null; then
        NIM_VERSION=$(nim --version | head -n 1)
        info "Nim already installed: $NIM_VERSION"
        return 0
    fi
    
    info "Installing Nim compiler via choosenim..."
    
    curl https://nim-lang.org/choosenim/init.sh -sSf | sh -s -- -y
    
    # Add to PATH for current session
    export PATH="$HOME/.nimble/bin:$PATH"
    
    # Add to shell profile
    if [ -f "$HOME/.bashrc" ]; then
        if ! grep -q ".nimble/bin" "$HOME/.bashrc"; then
            echo 'export PATH="$HOME/.nimble/bin:$PATH"' >> "$HOME/.bashrc"
        fi
    fi
    
    if [ -f "$HOME/.zshrc" ]; then
        if ! grep -q ".nimble/bin" "$HOME/.zshrc"; then
            echo 'export PATH="$HOME/.nimble/bin:$PATH"' >> "$HOME/.zshrc"
        fi
    fi
    
    info "✓ Nim compiler installed"
}

# Install Nim dependencies
install_nim_deps() {
    info "Installing Nim dependencies..."
    
    export PATH="$HOME/.nimble/bin:$PATH"
    
    # Install common dependencies for both implants
    nimble install -y nimcrypto
    nimble install -y parsetoml
    nimble install -y puppy
    
    # Install additional dependencies for Windows implant (if needed)
    if [ -f "implant/implant.nimble" ]; then
        info "Installing Windows implant dependencies..."
        nimble install -y pixie || warn "Failed to install pixie (optional)"
        nimble install -y ptr_math || warn "Failed to install ptr_math (optional)"
        nimble install -y winim || warn "Failed to install winim (Windows-only, expected to fail on Linux)"
        nimble install -y zippy || warn "Failed to install zippy (optional)"
        nimble install -y nimvoke || warn "Failed to install nimvoke (optional)"
    fi
    
    info "✓ Nim dependencies installed"
}

# Setup configuration
setup_config() {
    info "Setting up configuration..."
    
    if [ ! -f "config.toml" ]; then
        if [ -f "config.toml.example" ]; then
            cp config.toml.example config.toml
            info "Created config.toml from example"
        else
            error "config.toml.example not found!"
        fi
    else
        info "config.toml already exists"
    fi
    
    # Create necessary directories
    mkdir -p server/downloads
    mkdir -p server/logs
    mkdir -p server/uploads
    mkdir -p implant/release
    mkdir -p multi_implant/bin
    
    info "✓ Configuration setup complete"
}

# Setup for Replit environment
setup_replit() {
    info "Configuring for Replit environment..."
    
    # Get Replit domain
    if [ -n "$REPLIT_DEV_DOMAIN" ]; then
        REPLIT_DOMAIN="$REPLIT_DEV_DOMAIN"
    elif [ -n "$REPLIT_DOMAINS" ]; then
        REPLIT_DOMAIN=$(echo "$REPLIT_DOMAINS" | cut -d',' -f1)
    else
        warn "Could not detect Replit domain, using default"
        REPLIT_DOMAIN="localhost"
    fi
    
    info "Detected Replit domain: $REPLIT_DOMAIN"
    
    # Update config.toml with Replit domain if needed
    if grep -q "implantCallbackIp = \"0.0.0.0\"" config.toml; then
        sed -i "s/implantCallbackIp = \"0.0.0.0\"/implantCallbackIp = \"$REPLIT_DOMAIN\"/" config.toml
        info "Updated implantCallbackIp to $REPLIT_DOMAIN"
    fi
    
    # Ensure port 5000 is configured for admin API
    if grep -q "port = 9669" config.toml; then
        sed -i 's/port = 9669/port = 5000/' config.toml
        info "Updated admin API port to 5000 (required for Replit)"
    fi
    
    info "✓ Replit configuration complete"
}

# Main setup function
main() {
    echo ""
    info "Starting Nimhawk setup..."
    echo ""
    
    detect_os
    
    # Check if Replit
    if is_replit; then
        info "Running in Replit environment"
        REPLIT_ENV=true
    else
        info "Running in local/standard environment"
        REPLIT_ENV=false
    fi
    
    echo ""
    
    # Setup configuration first
    setup_config
    
    echo ""
    
    # Install Python dependencies
    install_python_deps
    
    echo ""
    
    # Install Nim
    install_nim
    
    echo ""
    
    # Install Nim dependencies
    install_nim_deps
    
    echo ""
    
    # Replit-specific setup
    if [ "$REPLIT_ENV" = true ]; then
        setup_replit
        echo ""
    fi
    
    echo "================================================"
    echo -e "${GREEN}✓ Setup Complete!${NC}"
    echo "================================================"
    echo ""
    echo "Next steps:"
    echo "  1. Review and customize config.toml"
    echo "  2. Start the backend: cd server && python main.py"
    echo "  3. Compile implants: cd multi_implant && make all"
    echo ""
    
    if [ "$REPLIT_ENV" = true ]; then
        echo "Replit-specific info:"
        echo "  - Admin API: https://$REPLIT_DOMAIN"
        echo "  - Implant callback: $REPLIT_DOMAIN"
        echo ""
    fi
    
    echo "For more information, see INSTALLATION.md"
    echo ""
}

# Run main function
main
