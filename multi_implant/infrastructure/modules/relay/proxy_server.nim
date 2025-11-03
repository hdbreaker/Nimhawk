# HTTP Proxy Server - Simple HTTP server for /proxy endpoint
import asyncdispatch, asynchttpserver, uri, strutils, tables
import proxy_handler
import ../../config/config_loader
from ../../adapters/string_obfuscation_adapter import obf

# Global proxy server instance
var g_proxyServer*: AsyncHttpServer
var g_proxyServerStarted*: bool = false

# Global config cache for GC-safe access (using cstring for GC-safety)
var g_cachedUserAgent*: cstring = nil
var g_cachedAllowKey*: cstring = nil

# Handle HTTP requests to /proxy endpoint
proc handleHttpRequest(req: Request) {.async, gcsafe.} =
  let path = req.url.path
  
  when defined debug:
    echo "[PROXY_SERVER] 🌐 Request: " & $req.reqMethod & " " & path
    echo "[PROXY_SERVER] 🌐 Headers: " & $req.headers
  
  # Handle /proxy endpoint
  if path == "/proxy" and req.reqMethod == HttpPost:
    try:
      let body = req.body
      when defined debug:
        echo "[PROXY_SERVER] 📨 POST /proxy - Body length: " & $body.len
      
      # Process proxy request using cached config
      if g_cachedUserAgent == nil or g_cachedAllowKey == nil:
        await req.respond(Http500, "ERROR: Config not loaded", newHttpHeaders([("Content-Type", "text/plain")]))
        return
      
      let result = handleProxyRequest(body, $g_cachedUserAgent, $g_cachedAllowKey)
      
      when defined debug:
        echo "[PROXY_SERVER] 📤 Response: " & result
      
      # Send successful response
      await req.respond(Http200, result, newHttpHeaders([
        ("Content-Type", "text/plain"),
        ("Access-Control-Allow-Origin", "*")
      ]))
      
    except Exception as e:
      when defined debug:
        echo "[PROXY_SERVER] ❌ Error handling /proxy: " & e.msg
      
      await req.respond(Http500, "ERROR: " & e.msg, newHttpHeaders([
        ("Content-Type", "text/plain")
      ]))
      
  # Handle /alive endpoint for health checks
  elif path == "/alive" and req.reqMethod == HttpGet:
    await req.respond(Http200, "OK", newHttpHeaders([
      ("Content-Type", "text/plain")
    ]))
    
  # Handle other endpoints
  else:
    when defined debug:
      echo "[PROXY_SERVER] ❌ Unsupported: " & $req.reqMethod & " " & path
    
    await req.respond(Http404, "Not Found", newHttpHeaders([
      ("Content-Type", "text/plain")
    ]))

# Start proxy server on specified port
proc startProxyServer*(port: int): bool =
  try:
    if g_proxyServerStarted:
      when defined debug:
        echo "[PROXY_SERVER] ⚠️ Server already started"
      return true
    
    # Load and cache config for GC-safe access
    let config = parseConfig()
    if config.hasKey(obf("userAgent")) and config.hasKey(obf("httpAllowCommunicationKey")):
      g_cachedUserAgent = cstring(config[obf("userAgent")])
      g_cachedAllowKey = cstring(config[obf("httpAllowCommunicationKey")])
    else:
      when defined debug:
        echo "[PROXY_SERVER] ❌ Missing required config keys"
      return false
    
    g_proxyServer = newAsyncHttpServer()
    
    when defined debug:
      echo "[PROXY_SERVER] 🚀 Starting HTTP proxy server on port " & $port
    
    # Start server asynchronously
    asyncCheck g_proxyServer.serve(Port(port), handleHttpRequest)
    g_proxyServerStarted = true
    
    when defined debug:
      echo "[PROXY_SERVER] ✅ HTTP proxy server started successfully on port " & $port
      echo "[PROXY_SERVER] 📍 Available endpoints:"
      echo "[PROXY_SERVER] 📍 - POST /proxy (main proxy endpoint)"
      echo "[PROXY_SERVER] 📍 - GET /alive (health check)"
    
    return true
    
  except Exception:
    when defined debug:
      echo "[PROXY_SERVER] ❌ Failed to start proxy server: " & getCurrentExceptionMsg()
    g_proxyServerStarted = false
    return false

# Stop proxy server
proc stopProxyServer*() =
  try:
    if g_proxyServerStarted and g_proxyServer != nil:
      g_proxyServer.close()
      g_proxyServerStarted = false
      when defined debug:
        echo "[PROXY_SERVER] 🛑 Proxy server stopped"
  except Exception:
    when defined debug:
      echo "[PROXY_SERVER] ❌ Error stopping proxy server: " & getCurrentExceptionMsg()

# Check if proxy server is running
proc isProxyServerRunning*(): bool =
  return g_proxyServerStarted

# Get proxy server port (if determinable)
proc getProxyServerPort*(): int =
  # For now, return the port that was used to start the server
  # In a full implementation, this could be stored as a global variable
  return 8080  # Default proxy port
