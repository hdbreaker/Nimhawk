#[
    Repository: SystemInfoRepository
    Implements SystemInfoPort
    Provides system information
]#

import ../util/sysinfo

type
    SystemInfoRepository* = object
        ## Repository for system information
        discard

proc newSystemInfoRepository*(): SystemInfoRepository =
    ## Create a new SystemInfoRepository instance
    result = SystemInfoRepository()

proc getLocalIP*(repo: SystemInfoRepository): string =
    ## Get local IP address
    result = sysinfo.getLocalIP()

proc getUsername*(repo: SystemInfoRepository): string =
    ## Get current username
    result = sysinfo.getUsername()

proc getHostname*(repo: SystemInfoRepository): string =
    ## Get system hostname
    result = sysinfo.getSysHostname()

proc getOSInfo*(repo: SystemInfoRepository): string =
    ## Get OS information
    result = sysinfo.getOSInfo()

proc getCurrentPID*(repo: SystemInfoRepository): int =
    ## Get current process ID
    result = sysinfo.getCurrentPID()

proc getCurrentProcessName*(repo: SystemInfoRepository): string =
    ## Get current process name
    result = sysinfo.getCurrentProcessName()

