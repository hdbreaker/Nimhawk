#[
    Cross-Platform curl Command
    HTTP client wrapper using native Nim httpclient
    Supports Linux, macOS, and other Unix systems
]#

import httpclient, strutils
import ../../util/strenc
import ../../core/webClientListener

# Cross-platform curl implementation using Nim httpclient
proc curl*(li: webClientListener.Listener, args: seq[string]): string =
    try:
        when defined verbose:
            echo obf("DEBUG: curl command with args: ") & $args
        
        if args.len == 0:
            return obf("ERROR: No URL provided")
        
        let url = args[0]
        var client = newHttpClient()
        defer: client.close()
        
        # Parse curl-like arguments
        var httpMethod = "GET"
        var headers: seq[(string, string)] = @[]
        var postData = ""
        var i = 1
        
        while i < args.len:
            case args[i]:
            of "-X", "--request":
                if i + 1 < args.len:
                    httpMethod = args[i + 1]
                    i += 2
                else:
                    return obf("ERROR: -X requires method argument")
            of "-H", "--header":
                if i + 1 < args.len:
                    let header = args[i + 1]
                    let parts = header.split(":", 1)
                    if parts.len == 2:
                        headers.add((parts[0].strip(), parts[1].strip()))
                    i += 2
                else:
                    return obf("ERROR: -H requires header argument")
            of "-d", "--data":
                if i + 1 < args.len:
                    postData = args[i + 1]
                    if httpMethod == "GET":
                        httpMethod = "POST"
                    i += 2
                else:
                    return obf("ERROR: -d requires data argument")
            of "-o", "--output":
                # Skip output file argument for now
                if i + 1 < args.len:
                    i += 2
                else:
                    return obf("ERROR: -o requires filename argument")
            else:
                i += 1
        
        # Set headers
        for (key, value) in headers:
            client.headers[key] = value
        
        when defined verbose:
            echo obf("DEBUG: Making ") & httpMethod & obf(" request to: ") & url
        
        var curlResult = ""
        
        case httpMethod.toUpper():
        of "GET":
            curlResult = client.getContent(url)
        of "POST":
            curlResult = client.postContent(url, postData)
        of "PUT":
            curlResult = client.request(url, httpMethod = HttpPut, body = postData).body
        of "DELETE":
            curlResult = client.request(url, httpMethod = HttpDelete).body
        of "HEAD":
            let response = client.request(url, httpMethod = HttpHead)
            for key, value in response.headers:
                curlResult.add(key & ": " & value & "\n")
        else:
            curlResult = client.request(url, httpMethod = httpMethod, body = postData).body
        
        when defined verbose:
            echo obf("DEBUG: curl response length: ") & $curlResult.len
        
        if curlResult.len > 0:
            return curlResult
        else:
            return obf("Empty response from server")
        
    except Exception as e:
        when defined verbose:
            echo obf("DEBUG: curl failed: ") & e.msg
        return obf("ERROR: curl failed - ") & e.msg 