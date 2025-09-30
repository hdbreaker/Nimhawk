#[
    HTTP Relay Server - Async HTTP Server
    Forwards HTTP requests with X-Next-Hop header
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
proc startRelayServer*(port: int, relayGuid: string = "") {.async.} =
    when defined debug:
        echo "[RELAY] 🚀 Starting async HTTP relay server on port " & $port
    
    var server = newAsyncHttpServer()
    
    proc handleRequest(req: Request) {.async.} =
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
                echo "[RELAY] ➡️  Forwarding to: " & nextHop
                if remainingHops != "":
                    echo "[RELAY] 📝 Remaining hops: " & remainingHops
            
            # Build target URL
            let targetUrl = "http://" & nextHop & req.url.path
            
            # Create HTTP client
            var client = newAsyncHttpClient()
            
            # Build forward headers
            var fwdHeaders = newHttpHeaders()
            for key, value in req.headers.pairs:
                let lowerKey = key.toLower()
                if lowerKey notin ["host", "connection", "content-length"]:
                    fwdHeaders[key] = value
            
            # Update or remove X-Next-Hop
            if remainingHops != "":
                fwdHeaders["X-Next-Hop"] = encryptNextHop(remainingHops)
            else:
                fwdHeaders.del("X-Next-Hop")
            
            # Add X-Relay-GUID if we have one
            if relayGuid != "":
                fwdHeaders["X-Relay-GUID"] = encryptRelayGuid(relayGuid)
            
            when defined debug:
                echo "[RELAY] 📤 Forwarding to: " & targetUrl
            
            # Forward request
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
