#!/bin/bash
# Relay Client Runner Script

echo "🚀 Starting Nimhawk Relay Client..."
echo "📍 Target Gateway: 192.168.0.6:6666"
echo ""

# Set permissions
chmod +x bin/nimhawk_darwin_intelx64

# Remove quarantine attributes
xattr -d com.apple.quarantine bin/nimhawk_darwin_intelx64 2>/dev/null || true

# Run with network permissions
exec ./bin/nimhawk_darwin_intelx64
