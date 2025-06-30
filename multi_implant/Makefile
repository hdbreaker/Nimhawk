# Multi-Platform Nimhawk Implant Makefile
# Supports Linux x86_64, ARM64, MIPS, ARM, and Darwin (Intel + Apple Silicon)

# Configuration
MAIN_FILE := main.nim
BIN_DIR := bin
CONFIG_FILE := ../../config.toml

# Nim compiler settings
NIM := nim c
NIM_FLAGS := -d:release -d:puppyLibcurl

# Optional flags
ifdef DEBUG
    NIM_FLAGS += -d:debug -d:verbose
    $(info 🐛 Debug mode enabled)
endif

ifdef VERBOSE
    $(info 🔧 Verbose mode enabled)
endif

# Fast mode for relay clients
ifdef FAST_MODE
    NIM_FLAGS += -d:FAST_MODE
    $(info 🚀 Fast mode enabled for relay client)
endif

# XOR Key (read from .xorkey file, can be overridden)
XOR_KEY := $(shell cat ../.xorkey 2>/dev/null || echo 459457925)

# Relay configuration (optional)
ifdef RELAY_ADDRESS
    RELAY_FLAGS := -d:RELAY_MODE -d:RELAY_ADDR:\"$(RELAY_ADDRESS)\"
    $(info 🔗 Relay mode enabled: $(RELAY_ADDRESS))
    
    # Optional relay server port for hybrid mode
    ifdef RELAY_SERVER_PORT
        RELAY_FLAGS += -d:RELAY_SERVER_PORT:$(RELAY_SERVER_PORT)
        $(info 🔗 Relay server port: $(RELAY_SERVER_PORT))
    endif
    
    # Relay role (client, server, hybrid)
    ifdef RELAY_ROLE
        RELAY_FLAGS += -d:RELAY_ROLE:\"$(RELAY_ROLE)\"
        $(info 🔗 Relay role: $(RELAY_ROLE))
    else
        RELAY_FLAGS += -d:RELAY_ROLE:\"client\"
        $(info 🔗 Relay role: client (default))
    endif
else
    RELAY_FLAGS :=
endif

# Check if config file exists
ifeq ($(wildcard $(CONFIG_FILE)),)
    $(warning Warning: config.toml not found at $(CONFIG_FILE), using defaults)
    CONFIG_EXISTS := false
else
    CONFIG_EXISTS := true
endif

# Create bin directory
$(BIN_DIR):
	@mkdir -p $(BIN_DIR)

# Linux x86_64 target
linux_x64: $(BIN_DIR)
	@echo "Building Linux x86_64 implant..."
	$(NIM) $(NIM_FLAGS) $(RELAY_FLAGS) \
		--os:linux --cpu:amd64 \
		-d:INITIAL_XOR_KEY=$(XOR_KEY) \
		-o:$(BIN_DIR)/nimhawk_linux_x64 \
		$(MAIN_FILE)
	@echo "✅ Linux x86_64 build complete: $(BIN_DIR)/nimhawk_linux_x64"

# Linux ARM64 target  
linux_arm64: $(BIN_DIR)
	@echo "Building Linux ARM64 implant..."
	$(NIM) $(NIM_FLAGS) $(RELAY_FLAGS) \
		--os:linux --cpu:arm64 \
		-d:INITIAL_XOR_KEY=$(XOR_KEY) \
		-o:$(BIN_DIR)/nimhawk_linux_arm64 \
		$(MAIN_FILE)
	@echo "✅ Linux ARM64 build complete: $(BIN_DIR)/nimhawk_linux_arm64"

# Linux MIPS Little-Endian target
linux_mipsel: $(BIN_DIR)
	@echo "Building Linux MIPS Little-Endian implant..."
	$(NIM) $(NIM_FLAGS) $(RELAY_FLAGS) \
		--os:linux --cpu:mips --endian:little \
		-d:INITIAL_XOR_KEY=$(XOR_KEY) \
		-o:$(BIN_DIR)/nimhawk_linux_mipsel \
		$(MAIN_FILE)
	@echo "✅ Linux MIPS Little-Endian build complete: $(BIN_DIR)/nimhawk_linux_mipsel"

# Linux ARM target
linux_arm: $(BIN_DIR)
	@echo "Building Linux ARM implant..."
	$(NIM) $(NIM_FLAGS) $(RELAY_FLAGS) \
		--os:linux --cpu:arm \
		-d:INITIAL_XOR_KEY=$(XOR_KEY) \
		-o:$(BIN_DIR)/nimhawk_linux_arm \
		$(MAIN_FILE)
	@echo "✅ Linux ARM build complete: $(BIN_DIR)/nimhawk_linux_arm"

# Darwin Intel x86_64 target
darwin_intelx64: $(BIN_DIR)
	@echo "Building Darwin Intel x86_64 implant..."
	@echo "🔑 Using XOR_KEY: $(XOR_KEY)"
	$(NIM) $(NIM_FLAGS) $(RELAY_FLAGS) \
		--os:macosx --cpu:amd64 \
		--passC:"-target x86_64-apple-macos11.0" \
		--passL:"-target x86_64-apple-macos11.0" \
		-d:INITIAL_XOR_KEY=$(XOR_KEY) \
		-o:$(BIN_DIR)/nimhawk_darwin_intelx64 \
		$(MAIN_FILE)
	@echo "✅ Darwin Intel x86_64 build complete: $(BIN_DIR)/nimhawk_darwin_intelx64"
	@echo "🔍 Verifying architecture..."
	@file $(BIN_DIR)/nimhawk_darwin_intelx64

# Darwin Apple Silicon ARM64 target
darwin_arm64: $(BIN_DIR)
	@echo "Building Darwin Apple Silicon ARM64 implant..."
	@echo "🔑 Using XOR_KEY: $(XOR_KEY)"
	$(NIM) $(NIM_FLAGS) \
		--os:macosx --cpu:arm64 \
		--passC:"-target arm64-apple-macos11.0" \
		--passL:"-target arm64-apple-macos11.0" \
		-d:INITIAL_XOR_KEY=$(XOR_KEY) \
		$(RELAY_FLAGS) \
		-o:$(BIN_DIR)/nimhawk_darwin_arm64 \
		$(MAIN_FILE)
	@echo "✅ Darwin Apple Silicon ARM64 build complete: $(BIN_DIR)/nimhawk_darwin_arm64"
	@echo "🔍 Verifying architecture..."
	@file $(BIN_DIR)/nimhawk_darwin_arm64

# Darwin (macOS) - Build both architectures
darwin: darwin_intelx64 darwin_arm64
	@echo ""
	@echo "🍎 Darwin universal build complete!"
	@echo "📁 Available Darwin binaries:"
	@echo "  - nimhawk_darwin_intelx64  (Intel x86_64)"
	@echo "  - nimhawk_darwin_arm64     (Apple Silicon ARM64)"

# Build all targets
all: linux_x64 linux_arm64 linux_mipsel linux_arm darwin
	@echo ""
	@echo "🚀 All multi-platform builds complete!"
	@echo "📁 Output directory: $(BIN_DIR)/"
	@ls -la $(BIN_DIR)/
	@echo ""
	@echo "📋 Available implants:"
	@echo "  - nimhawk_linux_x64       (Linux x86_64)"
	@echo "  - nimhawk_linux_arm64     (Linux ARM64)"
	@echo "  - nimhawk_linux_mipsel    (Linux MIPS Little-Endian)"
	@echo "  - nimhawk_linux_arm       (Linux ARM)"
	@echo "  - nimhawk_darwin_intelx64 (macOS Intel x86_64)"
	@echo "  - nimhawk_darwin_arm64    (macOS Apple Silicon ARM64)"

# Test compilation (syntax check only)
test: $(BIN_DIR)
	@echo "🧪 Testing compilation for all targets..."
	@echo "Testing Linux x86_64..."
	$(NIM) $(NIM_FLAGS) --os:linux --cpu:amd64 --compileOnly $(MAIN_FILE)
	@echo "Testing Linux ARM64..."
	$(NIM) $(NIM_FLAGS) --os:linux --cpu:arm64 --compileOnly $(MAIN_FILE)
	@echo "Testing Linux MIPS..."
	$(NIM) $(NIM_FLAGS) --os:linux --cpu:mips --compileOnly $(MAIN_FILE)
	@echo "Testing Linux ARM..."
	$(NIM) $(NIM_FLAGS) --os:linux --cpu:arm --compileOnly $(MAIN_FILE)
	@echo "Testing Darwin Intel x64..."
	$(NIM) $(NIM_FLAGS) --os:macosx --cpu:amd64 --compileOnly $(MAIN_FILE)
	@echo "Testing Darwin ARM64..."
	$(NIM) $(NIM_FLAGS) --os:macosx --cpu:arm64 --compileOnly $(MAIN_FILE)
	@echo "✅ All compilation tests passed!"

# Clean build artifacts
clean:
	@echo "🧹 Cleaning build artifacts..."
	@rm -rf $(BIN_DIR)
	@rm -f nimcache
	@echo "✅ Clean complete"

# Show help
help:
	@echo "Nimhawk Multi-Platform Implant Builder"
	@echo ""
	@echo "Usage: make [target] [OPTIONS]"
	@echo ""
	@echo "Targets:"
	@echo "  all           - Build all platforms"
	@echo "  linux_x64     - Build Linux x86_64"
	@echo "  linux_arm64   - Build Linux ARM64"
	@echo "  linux_mipsel  - Build Linux MIPS Little-Endian"
	@echo "  linux_arm     - Build Linux ARM"
	@echo "  darwin           - Build both macOS architectures"
	@echo "  darwin_intelx64  - Build macOS Intel x86_64"
	@echo "  darwin_arm64     - Build macOS Apple Silicon ARM64"
	@echo "  test          - Test compilation only"
	@echo "  clean         - Clean build artifacts"
	@echo "  help          - Show this help"
	@echo ""
	@echo "Options:"
	@echo "  XOR_KEY=123              - Set custom XOR key"
	@echo "  VERBOSE=1                - Enable verbose output"
	@echo "  DEBUG=1                  - Enable debug mode"
	@echo "  FAST_MODE=1              - Enable fast mode for relay clients (0.5-1s intervals)"
	@echo ""
	@echo "Relay Configuration:"
	@echo "  RELAY_ADDRESS=relay://ip:port  - Build as relay client"
	@echo "  RELAY_SERVER_PORT=9999         - Relay server port (hybrid mode)"
	@echo "  RELAY_ROLE=client|server       - Relay role (default: client)"
	@echo ""
	@echo "Examples:"
	@echo "  make darwin_arm64 DEBUG=1"
	@echo "  make darwin_arm64 RELAY_ADDRESS=relay://192.168.1.100:9999 DEBUG=1"
	@echo "  make darwin_arm64 RELAY_ADDRESS=relay://192.168.1.100:9999 FAST_MODE=1 DEBUG=1"

# Default target
.DEFAULT_GOAL := help

# Declare phony targets
.PHONY: all linux_x64 linux_arm64 linux_mipsel linux_arm darwin darwin_intelx64 darwin_arm64 test clean help 