import os, strutils, osproc, times

# Build validation script for Nimhawk multi-implant with unified routing system
echo "🔨 ═══════════════════════════════════════════════════════════════"
echo "🔨 NIMHAWK BUILD VALIDATION - UNIFIED ROUTING SYSTEM"
echo "🔨 ═══════════════════════════════════════════════════════════════"

# Build configurations to test
type
  BuildConfig = object
    name: string
    target: string
    defines: seq[string]
    extraFlags: seq[string]

let buildConfigs = @[
  BuildConfig(
    name: "Standard Debug Build",
    target: "main.nim",
    defines: @["DEBUG"],
    extraFlags: @["--hints:off", "--warnings:off"]
  ),
  BuildConfig(
    name: "Standard Release Build", 
    target: "main.nim",
    defines: @[],
    extraFlags: @["--hints:off", "--warnings:off", "-d:release"]
  ),
  BuildConfig(
    name: "Relay Client Debug Build",
    target: "main.nim", 
    defines: @["DEBUG"],
    extraFlags: @["--hints:off", "--warnings:off", "-d:RELAY_ADDRESS=relay://127.0.0.1:9999"]
  ),
  BuildConfig(
    name: "Fast Mode Debug Build",
    target: "main.nim",
    defines: @["DEBUG", "FAST_MODE"],
    extraFlags: @["--hints:off", "--warnings:off"]
  ),
  BuildConfig(
    name: "Test Suite Build",
    target: "tests/unit/test_all_routing.nim",
    defines: @["DEBUG"],
    extraFlags: @["--hints:off", "--warnings:off"]
  ),
  BuildConfig(
    name: "Integration Test Build",
    target: "tests/integration/test_unified_system_integration.nim", 
    defines: @["DEBUG"],
    extraFlags: @["--hints:off", "--warnings:off"]
  )
]

proc runBuild(config: BuildConfig): bool =
  echo ""
  echo "🔨 Building: " & config.name
  echo "🔨 Target: " & config.target
  
  # Build nim command
  var cmd = "nim c"
  
  # Add defines
  for define in config.defines:
    cmd.add(" -d:" & define)
  
  # Add extra flags
  for flag in config.extraFlags:
    cmd.add(" " & flag)
  
  # Add target
  cmd.add(" " & config.target)
  
  echo "🔨 Command: " & cmd
  
  # Execute build
  let startTime = cpuTime()
  let (output, exitCode) = execCmdEx(cmd)
  let buildTime = cpuTime() - startTime
  
  if exitCode == 0:
    echo "✅ Build successful (" & $buildTime.int & "s)"
    return true
  else:
    echo "❌ Build failed!"
    echo "Error output:"
    echo output
    return false

proc main() =
  var successCount = 0
  var failedBuilds: seq[string] = @[]
  
  echo ""
  echo "🔨 Starting build validation..."
  echo "🔨 Testing " & $buildConfigs.len & " build configurations"
  
  # Test each build configuration
  for config in buildConfigs:
    if runBuild(config):
      successCount += 1
    else:
      failedBuilds.add(config.name)
  
  # Summary
  echo ""
  echo "🔨 ═══════════════════════════════════════════════════════════════"
  echo "🔨 BUILD VALIDATION SUMMARY"
  echo "🔨 ═══════════════════════════════════════════════════════════════"
  echo "🔨 Total configurations: " & $buildConfigs.len
  echo "🔨 Successful builds: " & $successCount 
  echo "🔨 Failed builds: " & $failedBuilds.len
  
  if failedBuilds.len > 0:
    echo "🔨 Failed configurations:"
    for failed in failedBuilds:
      echo "🔨 • " & failed
  
  echo "🔨 ═══════════════════════════════════════════════════════════════"
  
  if successCount == buildConfigs.len:
    echo "🔨 ✅ ALL BUILDS SUCCESSFUL!"
    echo "🔨 🎯 Unified routing system is ready for deployment"
    quit(0)
  else:
    echo "🔨 ❌ SOME BUILDS FAILED!"
    echo "🔨 🚨 Please fix build issues before deployment"
    quit(1)

when isMainModule:
  main() 