declare module Types {
    // Implant info
    export interface NimplantOverview {
        id: string;
        guid: string;
        active: boolean;
        ipAddrExt: string;
        ipAddrInt: string;
        username: string;
        hostname: string;
        pid: number;
        lastCheckin: string;
        late: boolean;
        disconnected?: boolean;
        workspace_uuid?: string;
        workspace_name?: string;
    }
    
    // Detailed Nimplant information
    export interface Nimplant {
        id: string;
        guid: string;
        active: boolean;
        late: boolean;
        UNIQUE_XOR_KEY: string;
        ipAddrExt: string;
        ipAddrInt: string;
        username: string;
        hostname: string;
        osBuild: string;
        pid: number;
        pname: string;
        riskyMode: boolean;
        sleepTime: number;
        sleepJitter: number;
        killDate: string;
        firstCheckin: string;
        lastCheckin: string;
        pendingTasks: string;
        hostingFile: string;
        receivingFile: string;
        lastUpdate: string;
        command_count: number;
        checkin_count: number;
        data_transferred: number;
        lastSeenText?: string;
        disconnected?: boolean;
    }

    export interface ServerInfoConfig{
        killDate: string;
        listenerHost: string;
        listenerIp: string;
        listenerPort: number;
        listenerType: string;
        implantCallbackIp: string;
        managementIp: string;
        managementPort: number;
        registerPath: string;
        resultPath: string;
        riskyMode: boolean;
        sleepJitter: number;
        sleepTime: number;
        taskPath: string;
        userAgent: string;
    }

    export interface ServerInfo {
        config: Config;
        guid: string;
        name: string;
        xorKey: number;
    }
}

export default Types