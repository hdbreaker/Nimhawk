#[
    Infrastructure Adapter: RelayServerAdapter
    Handles HTTP proxy server operations
    Migrated from modules/relay/proxy_server.nim
]#

import asyncdispatch, asynchttpserver, uri, strutils, tables
import ../modules/relay/proxy_handler
from ../../infrastructure/config/config_loader import parseConfig

type
    RelayServerAdapter* = object
        server*: AsyncHttpServer
        isStarted*: bool
        port*: int
        cachedUserAgent*: cstring
        cachedAllowKey*: cstring

proc newRelayServerAdapter*(): RelayServerAdapter =
    ## Create a new RelayServerAdapter instance
    result = RelayServerAdapter(
        server: nil,
        isStarted: false,
        port: 0,
        cachedUserAgent: nil,
        cachedAllowKey: nil
    )

# Handle HTTP requests to /proxy endpoint
proc handleHttpRequest(adapter: RelayServerAdapter, req: Request) {.async, gcsafe.} =
    let path = req.url.path
    
    when defined debug:
        echo "[PROXY_SERVER] 🌐 Request: " & $req.reqMethod & " " & path
    
    # Handle /proxy endpoint
    if path == "/proxy" and req.reqMethod == HttpPost:
        try:
            let body = req.body
            when defined debug:
                echo "[PROXY_SERVER] 📨 POST /proxy - Body length: " & $body.len
            
            # Process proxy request using cached config
            if adapter.cachedUserAgent == nil or adapter.cachedAllowKey == nil:
                await req.respond(Http500, "ERROR: Config not loaded", newHttpHeaders([("Content-Type", "text/plain")]))
                return
            
            let result = handleProxyRequest(body, $adapter.cachedUserAgent, $adapter.cachedAllowKey)
            
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

proc startProxyServer*(adapter: var RelayServerAdapter, port: int): bool =
    ## Start proxy server on specified port
    try:
        if adapter.isStarted:
            when defined debug:
                echo "[PROXY_SERVER] ⚠️ Server already started"
            return true
        
        # Load and cache config for GC-safe access
        let CONFIG = parseConfig()
        if CONFIG.hasKey("userAgent") and CONFIG.hasKey("httpAllowCommunicationKey"):
            adapter.cachedUserAgent = cstring(CONFIG["userAgent"])
            adapter.cachedAllowKey = cstring(CONFIG["httpAllowCommunicationKey"])
        else:
            when defined debug:
                echo "[PROXY_SERVER] ❌ Missing required config keys"
            return false
        
        adapter.server = newAsyncHttpServer()
        adapter.port = port
        
        when defined debug:
            echo "[PROXY_SERVER] 🚀 Starting HTTP proxy server on port " & $port
        
        # Start server asynchronously
        asyncCheck adapter.server.serve(Port(port), proc(req: Request) {.async, gcsafe.} = await handleHttpRequest(adapter, req))
        adapter.isStarted = true
        
        when defined debug:
            echo "[PROXY_SERVER] ✅ HTTP proxy server started successfully on port " & $port
        
        return true
        
    except Exception as e:
        when defined debug:
            echo "[PROXY_SERVER] ❌ Failed to start server: " & e.msg
        return false

proc stopProxyServer*(adapter: var RelayServerAdapter) =
    ## Stop proxy server
    try:
        if adapter.server != nil and adapter.isStarted:
            adapter.server.close()
            adapter.isStarted = false
            adapter.server = nil
            
            when defined debug:
                echo "[PROXY_SERVER] ✅ HTTP proxy server stopped"
    except Exception as e:
        when defined debug:
            echo "[PROXY_SERVER] ❌ Error stopping server: " & e.msg

proc isProxyServerRunning*(adapter: RelayServerAdapter): bool =
    ## Check if proxy server is running
    return adapter.isStarted

