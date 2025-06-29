# Multi-Platform Nimhawk Implant Makefile
# Supports Linux x86_64, ARM64, MIPS, ARM, and Darwin

# Configuration
MAIN_FILE := main.nim
BIN_DIR := bin
CONFIG_FILE := ../../config.toml

# Nim compiler settings
NIM := nim c
NIM_FLAGS := -d:release -d:puppyLibcurl

# XOR Key (read from .xorkey file, can be overridden)
XOR_KEY := $(shell cat ../.xorkey 2>/dev/null || echo 459457925)

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
	$(NIM) $(NIM_FLAGS) \
		--os:linux --cpu:amd64 \
		-d:INITIAL_XOR_KEY=$(XOR_KEY) \
		-o:$(BIN_DIR)/nimhawk_linux_x64 \
		$(MAIN_FILE)
	@echo "✅ Linux x86_64 build complete: $(BIN_DIR)/nimhawk_linux_x64"

# Linux ARM64 target  
linux_arm64: $(BIN_DIR)
	@echo "Building Linux ARM64 implant..."
	$(NIM) $(NIM_FLAGS) \
		--os:linux --cpu:arm64 \
		-d:INITIAL_XOR_KEY=$(XOR_KEY) \
		-o:$(BIN_DIR)/nimhawk_linux_arm64 \
		$(MAIN_FILE)
	@echo "✅ Linux ARM64 build complete: $(BIN_DIR)/nimhawk_linux_arm64"

# Linux MIPS Little-Endian target
linux_mipsel: $(BIN_DIR)
	@echo "Building Linux MIPS Little-Endian implant..."
	$(NIM) $(NIM_FLAGS) \
		--os:linux --cpu:mips --endian:little \
		-d:INITIAL_XOR_KEY=$(XOR_KEY) \
		-o:$(BIN_DIR)/nimhawk_linux_mipsel \
		$(MAIN_FILE)
	@echo "✅ Linux MIPS Little-Endian build complete: $(BIN_DIR)/nimhawk_linux_mipsel"

# Linux ARM target
linux_arm: $(BIN_DIR)
	@echo "Building Linux ARM implant..."
	$(NIM) $(NIM_FLAGS) \
		--os:linux --cpu:arm \
		-d:INITIAL_XOR_KEY=$(XOR_KEY) \
		-o:$(BIN_DIR)/nimhawk_linux_arm \
		$(MAIN_FILE)
	@echo "✅ Linux ARM build complete: $(BIN_DIR)/nimhawk_linux_arm"

# Darwin (macOS) target
darwin: $(BIN_DIR)
	@echo "Building Darwin (macOS) implant..."
	@echo "🔑 Using XOR_KEY: $(XOR_KEY)"
	$(NIM) $(NIM_FLAGS) \
		--os:macosx --cpu:amd64 \
		-d:INITIAL_XOR_KEY=$(XOR_KEY) \
		-o:$(BIN_DIR)/nimhawk_darwin \
		$(MAIN_FILE)
	@echo "✅ Darwin build complete: $(BIN_DIR)/nimhawk_darwin"

# Build all targets
all: linux_x64 linux_arm64 linux_mipsel linux_arm darwin
	@echo ""
	@echo "🚀 All multi-platform builds complete!"
	@echo "📁 Output directory: $(BIN_DIR)/"
	@ls -la $(BIN_DIR)/
	@echo ""
	@echo "📋 Available implants:"
	@echo "  - nimhawk_linux_x64     (Linux x86_64)"
	@echo "  - nimhawk_linux_arm64   (Linux ARM64)"
	@echo "  - nimhawk_linux_mipsel  (Linux MIPS Little-Endian)"
	@echo "  - nimhawk_linux_arm     (Linux ARM)"
	@echo "  - nimhawk_darwin        (macOS)"

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
	@echo "Testing Darwin..."
	$(NIM) $(NIM_FLAGS) --os:macosx --cpu:amd64 --compileOnly $(MAIN_FILE)
	@echo "✅ All compilation tests passed!"

# Debug builds (with verbose output)
debug: $(BIN_DIR)
	@echo "🐛 Building debug version (Linux x64)..."
	$(NIM) -d:debug -d:verbose -d:puppyLibcurl \
		--os:linux --cpu:amd64 \
		-d:INITIAL_XOR_KEY=$(XOR_KEY) \
		-o:$(BIN_DIR)/nimhawk_debug \
		$(MAIN_FILE)
	@echo "✅ Debug build complete: $(BIN_DIR)/nimhawk_debug"

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
	@echo "Usage: make [target]"
	@echo ""
	@echo "Targets:"
	@echo "  all           - Build all platforms"
	@echo "  linux_x64     - Build Linux x86_64"
	@echo "  linux_arm64   - Build Linux ARM64"
	@echo "  linux_mipsel  - Build Linux MIPS Little-Endian"
	@echo "  linux_arm     - Build Linux ARM"
	@echo "  darwin        - Build macOS"
	@echo "  test          - Test compilation only"
	@echo "  debug         - Build debug version"
	@echo "  clean         - Clean build artifacts"
	@echo "  help          - Show this help"
	@echo ""
	@echo "Options:"
	@echo "  XOR_KEY=123   - Set custom XOR key"
	@echo ""
	@echo "Examples:"
	@echo "  make all"
	@echo "  make linux_x64 XOR_KEY=987654321"
	@echo "  make test"

# Default target
.DEFAULT_GOAL := help

# Declare phony targets
.PHONY: all linux_x64 linux_arm64 linux_mipsel linux_arm darwin test debug clean help 