#!/bin/bash

echo "=== Testing Build Configurations ==="
echo ""

# Test 1: Standard build (no relay)
echo "1️⃣ Testing STANDARD build (no relay)..."
make darwin_arm64 DEBUG=1 > /tmp/build1.log 2>&1
if [ $? -eq 0 ]; then
    echo "   ✅ Standard build: PASSED"
    grep -q "RELAY_CHAIN\|RELAY_PORT" /tmp/build1.log && echo "   ⚠️  Warning: Relay flags present" || echo "   ✓ No relay flags (expected)"
else
    echo "   ❌ Standard build: FAILED"
    tail -20 /tmp/build1.log
fi
echo ""

# Test 2: Build with RELAY_CHAIN (HTTP proxy)
echo "2️⃣ Testing RELAY_CHAIN build (HTTP proxy)..."
make darwin_arm64 RELAY_CHAIN=relay1.com:8080,c2.com:5000 DEBUG=1 > /tmp/build2.log 2>&1
if [ $? -eq 0 ]; then
    echo "   ✅ RELAY_CHAIN build: PASSED"
    grep "Relay chain:" /tmp/build2.log || echo "   ⚠️  Warning: Missing relay chain log"
    grep "RELAY_CHAIN_TARGET" /tmp/build2.log && echo "   ✓ RELAY_CHAIN_TARGET flag present" || echo "   ⚠️  RELAY_CHAIN_TARGET not found"
else
    echo "   ❌ RELAY_CHAIN build: FAILED"
    tail -20 /tmp/build2.log
fi
echo ""

# Test 3: Build with RELAY_PORT (relay server)
echo "3️⃣ Testing RELAY_PORT build (relay server)..."
make darwin_arm64 RELAY_PORT=8080 DEBUG=1 > /tmp/build3.log 2>&1
if [ $? -eq 0 ]; then
    echo "   ✅ RELAY_PORT build: PASSED"
    grep "listening on port" /tmp/build3.log || echo "   ⚠️  Warning: Missing relay port log"
else
    echo "   ❌ RELAY_PORT build: FAILED"
    tail -20 /tmp/build3.log
fi
echo ""

# Test 4: Combined RELAY_CHAIN + RELAY_PORT
echo "4️⃣ Testing RELAY_CHAIN + RELAY_PORT (chained relay server)..."
make darwin_arm64 RELAY_CHAIN=relay2.com:8080,c2.com:5000 RELAY_PORT=8080 DEBUG=1 > /tmp/build4.log 2>&1
if [ $? -eq 0 ]; then
    echo "   ✅ Combined build: PASSED"
    grep "Relay chain:" /tmp/build4.log && echo "   ✓ Chain configured"
    grep "listening on port" /tmp/build4.log && echo "   ✓ Server configured"
else
    echo "   ❌ Combined build: FAILED"
    tail -20 /tmp/build4.log
fi
echo ""

echo "=== Build Test Summary ==="
ls -lh bin/nimhawk_darwin_arm64 2>/dev/null && echo "✅ Binary created successfully" || echo "❌ No binary found"
