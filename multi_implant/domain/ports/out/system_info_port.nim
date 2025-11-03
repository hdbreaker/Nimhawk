#[
    Port OUT: SystemInfoPort
    Interface for system information retrieval (provided by infrastructure)
]#

type
    SystemInfoPort* = concept
        ## Port for retrieving system information
        proc getLocalIP*(self): string
        proc getUsername*(self): string
        proc getHostname*(self): string
        proc getOSInfo*(self): string
        proc getCurrentPID*(self): int
        proc getCurrentProcessName*(self): string

