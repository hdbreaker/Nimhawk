export const SERVER_BASE_URL = `${process.env.SERVER_IP}:${process.env.SERVER_PORT}` as string;
export const IMPLANT_BASE_URL = `${process.env.IMPLANT_SERVER_IP}:${process.env.IMPLANT_SERVER_PORT}` as string;

// Create helper function to get server URL
export const getServerEndpoint = () => {
    // Get updated URL on each call
    const ADMIN_SERVER_URL = SERVER_BASE_URL;
    return `${ADMIN_SERVER_URL}/api/server`;
}

// Create helper function to get implant alive endpoint
export const getImplantEndpoint = () => {
    // Get updated URL on each call
    const IMPLANT_SERVER_URL = IMPLANT_BASE_URL;
    return `${IMPLANT_SERVER_URL}/alive`;
}