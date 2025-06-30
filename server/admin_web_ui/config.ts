// Build SERVER_BASE_URL with proper defaults and protocol
const adminServerIP = process.env.NEXT_PUBLIC_NIMHAWK_ADMIN_SERVER_IP || 'http://localhost';
const adminServerPort = process.env.NEXT_PUBLIC_NIMHAWK_ADMIN_SERVER_PORT || '9669';

// Ensure we have the protocol
const baseIP = adminServerIP.startsWith('http://') || adminServerIP.startsWith('https://') 
    ? adminServerIP 
    : `http://${adminServerIP}`;

export const SERVER_BASE_URL = `${baseIP}:${adminServerPort}` as string;

// Debug log to see what URL is being generated
console.log('SERVER_BASE_URL configured as:', SERVER_BASE_URL);

// Create helper function to get server URL
export const getServerEndpoint = () => {
    // Get updated URL on each call
    const ADMIN_SERVER_URL = SERVER_BASE_URL;
    return `${ADMIN_SERVER_URL}/api/server`;
}

// Function to get implant endpoint from server configuration (dynamically)
export const getImplantEndpointFromConfig = (serverConfig: any) => {
    if (!serverConfig || !serverConfig.implants_server) {
        return '';
    }
    
    const implants_server = serverConfig.implants_server;
    const protocol = implants_server.type === "HTTPS" ? "https://" : "http://";
    const ip = implants_server.ip;
    
    // Always show port for clarity in C2 operations
    const port = implants_server.port ? `:${implants_server.port}` : '';
    
    return `${protocol}${ip}${port}`;
}