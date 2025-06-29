# Multi-Platform Nimhawk Implant Package
version       = "1.4.0"
author        = "hdbreaker"
description   = "Cross-platform implant for Nimhawk C2 framework - Linux, ARM, MIPS, Darwin"
license       = "MIT"
srcDir        = "."
skipDirs      = @["bin"]

# Dependencies matching Windows implant exactly
requires "nim >= 1.6.10"
requires "nimcrypto >= 0.6.0"
requires "parsetoml >= 0.7.1"
requires "puppy >= 2.1.0"

task build, "Build multi-platform implants":
    echo "Building multi-platform implants..."
    exec "make all"

task clean, "Clean build artifacts":
    echo "Cleaning build artifacts..."
    exec "make clean"

task test, "Test compilation for all targets":
    echo "Testing compilation..."
    exec "make test" 