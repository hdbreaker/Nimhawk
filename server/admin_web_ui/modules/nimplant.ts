import { notifications } from '@mantine/notifications';
import { parse, format, formatDistanceToNow } from 'date-fns';
import useSWR from 'swr'
import Types from './nimplant.d'
import { SERVER_BASE_URL } from '../config';
import { swrFetcher, api } from './apiFetcher';
import { nanoid } from 'nanoid';
import { isValidGuid } from './utils';

// Define and export endpoints as a constant using centralized base URL
export const endpoints = {
    commands: `${SERVER_BASE_URL}/api/commands`,
    downloads: `${SERVER_BASE_URL}/api/downloads`,
    server: `${SERVER_BASE_URL}/api/server`,
    serverExit: `${SERVER_BASE_URL}/api/server/exit`,
    upload: `${SERVER_BASE_URL}/api/upload`,
    nimplants: `${SERVER_BASE_URL}/api/nimplants`,
    nimplantInfo: (guid: string) => `${SERVER_BASE_URL}/api/nimplants/${guid}`,
    nimplantExit: (guid: string) => `${SERVER_BASE_URL}/api/nimplants/${guid}/exit`,
    nimplantCommand: (guid: string) => `${SERVER_BASE_URL}/api/nimplants/${guid}/command`,
    nimplantConsole: (guid: string, lines = 1000, offset = 0) => `${SERVER_BASE_URL}/api/nimplants/${guid}/console/${lines}/${offset}?order=desc`,
    nimplantHistory: (guid: string, lines = 1000, offset = 0) => `${SERVER_BASE_URL}/api/nimplants/${guid}/history/${lines}`,
    build: `${SERVER_BASE_URL}/api/build`,
    getDownload: (filename: string) => `${SERVER_BASE_URL}/api/get-download/${filename}`,
    fileTransfers: `${SERVER_BASE_URL}/api/file-transfers`,
    buildStatus: `${SERVER_BASE_URL}/api/build/status`,
    buildOptions: `${SERVER_BASE_URL}/api/build/options`,
    uploads: `${SERVER_BASE_URL}/api/upload`,
    auth: {
        login: `${SERVER_BASE_URL}/api/auth/login`,
        logout: `${SERVER_BASE_URL}/api/auth/logout`,
        verify: `${SERVER_BASE_URL}/api/auth/verify`
    },
    workspaces: `${SERVER_BASE_URL}/api/workspaces`
}

// Define the fetcher with authentication
const fetcher = (url: any) => {
  // Get token with extra debugging
  let token = null;
  
  try {
    if (typeof window !== 'undefined') {
      token = localStorage.getItem('auth_token');
      console.log(`${url}: Token exists: ${!!token}`);
      if (!token) {
        console.warn(`${url}: No token available for request`);
        if (url.includes('/api/') && !url.includes('/api/auth/login')) {
          console.error(`${url}: Missing auth token, redirecting to login`);
          window.location.href = '/login';
          throw new Error('Authentication required');
        }
      }
    }
  } catch (e) {
    console.error(`${url}: Error accessing localStorage:`, e);
  }
  
  // Create headers with Authorization if token exists
  const headers: Record<string, string> = {
    'Content-Type': 'application/json'
  };
  
  if (token) {
    headers['Authorization'] = `Bearer ${token}`;
    console.log(`${url}: Using auth header: Bearer ${token.substring(0, 5)}...`);
  }
  
  return fetch(url, {
    headers,
    credentials: 'include'
  }).then(r => {
    console.log(`${url}: Response status: ${r.status}`);
    
    if (r.status === 401) {
      // If unauthorized, clear token and redirect to login
      console.error(`${url}: Authentication failed (401), redirecting`);
      if (typeof window !== 'undefined') {
        localStorage.removeItem('auth_token');
        window.location.href = '/login';
        throw new Error('Authentication required');
      }
    }
    
    if (!r.ok) {
      throw new Error(`${url}: Server error ${r.status}`);
    }
    
    return r.json();
  }).catch(error => {
    console.error(`${url}: Error fetching:`, error);
    throw error;
  });
}

//
//  GET functions
//

export function getCommands () {
    const { data, error } = useSWR(endpoints.commands, swrFetcher)

    return {
        commandList: data,
        commandListLoading: !error && !data,
        commandListError: error
    }
}

export function getDownloads () {
    const { data, error } = useSWR(endpoints.downloads, swrFetcher,  { refreshInterval: 5000 })

    return {
        downloads: data,
        downloadsLoading: !error && !data,
        downloadsError: error
    }
}

export function getBuildOptions () {
    const { data, error } = useSWR(endpoints.buildOptions, swrFetcher)

    return {
        buildOptions: data,
        buildOptionsLoading: !error && !data,
        buildOptionsError: error
    }
}

export function getServerInfo () {
    console.log('getServerInfo called, endpoint:', endpoints.server);
    
    // Debug token retrieval specifically for this call
    if (typeof window !== 'undefined') {
        const token = localStorage.getItem('auth_token');
        console.log('Current auth token exists:', !!token);
    }
    
    const { data, error, mutate } = useSWR(endpoints.server, swrFetcher, {
        onError: (err) => {
            console.error('Error fetching server info:', err);
        },
        revalidateOnFocus: false,
        revalidateOnMount: true,
        dedupingInterval: 5000
    });

    // Debug the data received
    if (data) {
        console.log('Server info received successfully');
    }

    return {
        serverInfo: data,
        serverInfoLoading: !error && !data,
        serverInfoError: error,
        refreshServerInfo: mutate
    }
}

export function getNimplants () {
    const { data, error } = useSWR(endpoints.nimplants, swrFetcher, { refreshInterval: 2500 })

    return {
        nimplants: data,
        nimplantsLoading: !error && !data,
        nimplantsError: error
    }
}

export function getNimplantInfo(guid: string | null | undefined) {
    // Validate GUID before making the request
    if (!isValidGuid(guid)) {
        return {
            nimplantInfo: null,
            nimplantInfoLoading: false,
            nimplantInfoError: new Error('Invalid GUID')
        };
    }

    const { data, error } = useSWR<Types.Nimplant>(endpoints.nimplantInfo(guid as string), swrFetcher, { refreshInterval: 5000 })

    return {
        nimplantInfo: data,
        nimplantInfoLoading: !error && !data,
        nimplantInfoError: error
    }
}

export function getNimplantConsole (guid: string | null | undefined, lines = 5000) {
    // Validate GUID before making the request
    if (!isValidGuid(guid)) {
        return {
            nimplantConsole: [],
            nimplantConsoleLoading: false,
            nimplantConsoleError: new Error('Invalid GUID')
        };
    }

    const { data, error } = useSWR(endpoints.nimplantConsole(guid as string, lines), swrFetcher, { 
        refreshInterval: 1000,
        onSuccess: (data) => {
            // Diagnostic log
            console.log('Data received from console:', data);
            if (data && Array.isArray(data) && data.length > 0) {
                // Show the last 2 messages for diagnostics
                console.log('Last messages:', data.slice(-2));
            }
        }
    });

    return {
        nimplantConsole: data || [],
        nimplantConsoleLoading: !error && !data,
        nimplantConsoleError: error
    };
}


//
// POST functions
//

export function serverExit(): void {
    notifications.show({
        id: 'server-exit',
        loading: true,
        title: 'Shutting down server...',
        message: 'Please wait while the server shuts down',
        color: 'yellow',
        autoClose: false,
    });
    
    api.post(endpoints.serverExit, {})
        .then(() => {
            notifications.update({
                id: 'server-exit',
                title: 'OK',
                message: 'Server is shutting down',
                color: 'green',
                loading: false,
                autoClose: 5000
            });
        })
        .catch((error) => {
            notifications.update({
                id: 'server-exit',
                title: 'Error',
                message: `Error shutting down server: ${error.message}`,
                color: 'red',
                loading: false,
                autoClose: 5000
            });
        });
}

// Build implant function
export const buildImplant = async (
    debug: boolean, 
    callback: (data: any) => void, 
    workspace?: string | null,
    implantType: string = "windows",
    architecture?: string | null,
    relayConfig?: any
) => {
    try {
        // Get auth token
        const token = localStorage.getItem('auth_token');
        
        // Prepare build request
        const requestOptions = {
            method: 'POST',
            headers: { 
                'Content-Type': 'application/json',
                ...(token ? { 'Authorization': `Bearer ${token}` } : {})
            },
            body: JSON.stringify({ 
                debug: debug,
                workspace: workspace || '',
                implant_type: implantType,
                architecture: architecture,
                relay_config: relayConfig
            })
        };
        
        // Correct the build endpoint URL - remove /start
        const response = await fetch(`${endpoints.build}`, requestOptions);
        
        if (response.ok) {
            const data = await response.json();
            callback(data);
        } else {
            console.error('Error starting build:', await response.text());
            callback(null);
        }
    } catch (error) {
        console.error('Error in buildImplant function:', error);
        callback(null);
    }
};

export const nimplantExit = async (guid: string) => {
  // Set up notifications
  const notification_ids: string[] = []
  const killNimplantId = nanoid()
  notification_ids.push(killNimplantId)

  notifications.show({
    id: killNimplantId,
    loading: true,
    title: 'Killing implant',
    message: 'Killing Implant',
    autoClose: false,
    withCloseButton: false,
  })

  try {
    // Get authentication token
    let token = null;
    if (typeof window !== 'undefined') {
      token = localStorage.getItem('auth_token');
      console.log(`Kill implant: Token exists: ${!!token}`);
    }

    // Build headers with authentication token
    const headers: Record<string, string> = {
      'Content-Type': 'application/json'
    };

    if (token) {
      headers['Authorization'] = `Bearer ${token}`;
      console.log(`Kill implant: Using auth header with token`);
    }

    console.log(`Sending kill command to implant ${guid}`);
    
    const response = await fetch(`${SERVER_BASE_URL}/api/nimplants/${guid}/exit`, {
      method: 'POST',
      headers,
      credentials: 'include',
    })

    console.log(`Kill implant response status: ${response.status}`);

    if (response.ok) {
      // Update notifications upon success
      notifications.update({
        id: killNimplantId,
        color: 'teal',
        title: 'Implant killed',
        message: 'Implant has been killed',
        autoClose: 2000,
        loading: false,
      })

      return true
    } else {
      const responseText = await response.text();
      console.error(`Error killing implant. Status: ${response.status}, Response: ${responseText}`);
      let errorMessage = `Error killing Implant (HTTP ${response.status})`;
      
      try {
        const errorData = JSON.parse(responseText);
        if (errorData.error || errorData.message) {
          errorMessage = errorData.error || errorData.message;
        }
      } catch (e) {
        // If not JSON, use the response text
        if (responseText) {
          errorMessage = responseText;
        }
      }
      
      throw new Error(errorMessage);
    }
  } catch (error: any) {
    notifications.update({
      id: killNimplantId,
      color: 'red',
      title: 'Error',
      message: `Error killing Implant: ${error.message || 'Unknown error'}`,
      autoClose: 2000,
      loading: false,
    })
    return false
  }
}

export const deleteNimplant = async (guid: string) => {
  // Set up notifications
  const notification_ids: string[] = []
  const deleteNimplantId = nanoid()
  notification_ids.push(deleteNimplantId)

  notifications.show({
    id: deleteNimplantId,
    loading: true,
    title: 'Deleting implant',
    message: 'Removing implant from database',
    autoClose: false,
    withCloseButton: false,
  })

  try {
    // Get authentication token
    let token = null;
    if (typeof window !== 'undefined') {
      token = localStorage.getItem('auth_token');
      console.log(`Delete implant: Token exists: ${!!token}`);
    }

    // Build headers with authentication token
    const headers: Record<string, string> = {
      'Content-Type': 'application/json'
    };

    if (token) {
      headers['Authorization'] = `Bearer ${token}`;
      console.log(`Delete implant: Using auth header with token`);
    }

    console.log(`Sending delete request for implant ${guid}`);
    
    const response = await fetch(`${SERVER_BASE_URL}/api/nimplants/${guid}`, {
      method: 'DELETE',
      headers,
      credentials: 'include',
    })

    console.log(`Delete implant response status: ${response.status}`);

    if (response.ok) {
      // Update notifications upon success
      notifications.update({
        id: deleteNimplantId,
        color: 'teal',
        title: 'Implant deleted',
        message: 'Implant has been removed from the database',
        autoClose: 2000,
        loading: false,
      })

      return true
    } else {
      const responseText = await response.text();
      console.error(`Error deleting implant. Status: ${response.status}, Response: ${responseText}`);
      let errorMessage = `Error deleting Implant (HTTP ${response.status})`;
      
      try {
        const errorData = JSON.parse(responseText);
        if (errorData.error || errorData.message) {
          errorMessage = errorData.error || errorData.message;
        }
      } catch (e) {
        // If not JSON, use the response text
        if (responseText) {
          errorMessage = responseText;
        }
      }
      
      throw new Error(errorMessage);
    }
  } catch (error: any) {
    notifications.update({
      id: deleteNimplantId,
      color: 'red',
      title: 'Error',
      message: `Error deleting Implant: ${error.message || 'Unknown error'}`,
      autoClose: 2000,
      loading: false,
    })
    return false
  }
}

export function submitCommand(guid: string | null | undefined, command: string, _callback: Function = () => {}): void {
    // Validate GUID before making the request
    if (!isValidGuid(guid)) {
        notifications.show({
            title: 'Error',
            message: 'Invalid GUID. Cannot send command.',
            color: 'red'
        });
        return;
    }

    // Validate command is not empty
    if (!command || command.trim() === '') {
        notifications.show({
            title: 'Error',
            message: 'Empty command. Nothing to send.',
            color: 'red'
        });
        return;
    }

    api.post(endpoints.nimplantCommand(guid as string), { command })
        .then(() => {
            notifications.show({
                title: 'OK',
                message: 'Command \''+ command.split(' ')[0] + '\' submitted',
                color: 'green',
            });
            _callback();
        })
        .catch((error) => {
            notifications.show({
                title: 'Error',
                message: `Error sending command: ${error.message}`,
                color: 'red',
            });
        });
}

export function uploadFile(file: File, _callbackCommand: Function = () => {}, _callbackClose: Function = () => {}): void {
    // Validate that the file is not null
    if (!file) {
        notifications.show({
            title: 'Error',
            message: 'No file selected for upload',
            color: 'red'
        });
        return;
    }

    // Warn if file size is too large (>5MB)
    if (file.size > 5242880) {
        if (!confirm("The selected file is larger than 5MB, which may cause unpredictable behavior.\nAre you sure you want to continue?")) {
            _callbackClose()
            return;
        }
    }
    
    // Upload file to server
    const formData = new FormData();
    formData.append('file', file);
    formData.append('filename', file.name);

    // Use our centralized API upload function
    api.upload(endpoints.upload, formData)
        .then((data) => {
            notifications.show({
                title: 'OK',
                message: 'File uploaded to server',
                color: 'green',
            });
            _callbackCommand(data.path);
        })
        .catch((error) => {
            notifications.show({
                title: 'Error',
                message: `Upload failed: ${error.message}`,
                color: 'red',
            });
        });
}


//
// UTILITY functions
//

// Format a date string from the server into a human readable string
export function timeSince(date: string | number): string {
  

  // If we don't have a date, return 'Unknown'
  if (!date) {
    //console.log("No date provided");
    return 'Unknown';
  }

  let dateObj: Date;
  
  try {
    // Try to parse as ISO date string
    if (typeof date === 'string') {
      // Try several possibilities:
      
      // ISO format
      try {
        dateObj = new Date(date);
        // Verify if the date is valid
        if (isNaN(dateObj.getTime())) {
          throw new Error('Invalid date format (ISO attempt)');
        }
      } catch (e) {
        // Unix timestamp format in ms (as string)
        try {
          dateObj = new Date(parseInt(date));
          if (isNaN(dateObj.getTime())) {
            throw new Error('Invalid date format (numeric timestamp attempt)');
          }
        } catch (e2) {
          console.error('Could not parse date:', date, e2);
          return 'Unknown';
        }
      }
    } else {
      // It's a number, assume Unix timestamp
      dateObj = new Date(date);
    }
    
    // If we get here, we have a valid date
    const now = new Date();
    const secondsPast = (now.getTime() - dateObj.getTime()) / 1000;
    
    if (secondsPast < 60) {
      return 'moments ago';
    }
    if (secondsPast < 3600) {
      return `${Math.floor(secondsPast / 60)} minutes ago`;
    }
    if (secondsPast < 86400) {
      return `${Math.floor(secondsPast / 3600)} hours ago`;
    }
    if (secondsPast < 604800) {
      return `${Math.floor(secondsPast / 86400)} days ago`;
    }
    if (secondsPast < 2592000) {
      return `${Math.floor(secondsPast / 604800)} weeks ago`;
    }
    if (secondsPast < 31536000) {
      return `${Math.floor(secondsPast / 2592000)} months ago`;
    }
    return `${Math.floor(secondsPast / 31536000)} years ago`;
  } catch (e) {
    console.error('Error calculating time:', e);
    return 'Unknown';
  }
}

// Format a number of bytes into a human readable string
export function formatBytes(bytes: number): string {
    if (bytes === 0) return '0 B';
    const k = 1024;
    const dm = 1;
    const sizes = ['B', 'KB', 'MB', 'GB', 'TB', 'PB', 'EB', 'ZB', 'YB'];
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    return parseFloat((bytes / Math.pow(k, i)).toFixed(dm)) + ' ' + sizes[i];
}

// Format an epoch timestamp into a human readable string
export function formatTimestamp(timestamp: number): string {
    return format(new Date(timestamp * 1000), 'yyyy/MM/dd HH:mm:ss')
}

// Listeners for time updates synchronization
type TimeUpdateListener = () => void;
const timeUpdateListeners: TimeUpdateListener[] = [];
let timeUpdateInterval: NodeJS.Timeout | null = null;

// Start the global timer for synchronization
export function startGlobalTimeUpdates() {
    if (timeUpdateInterval) return; // Already started
    
    // Calculate seconds until next update at 15-minute interval
    const now = new Date();
    const minutes = now.getMinutes();
    const seconds = now.getSeconds();
    
    // Find time until next 15-minute mark (0, 15, 30, 45)
    const nextQuarter = Math.ceil(minutes / 15) * 15;
    const minutesUntilNext = nextQuarter - minutes;
    const secondsUntilNext15 = (minutesUntilNext * 60) - seconds;
    
    console.log(`Global timer started. Synchronizing in ${secondsUntilNext15} seconds`);

    // First wait until aligned with 15-second intervals
    setTimeout(() => {
        // Notify all components immediately
        notifyTimeListeners();
        
        // Set the interval aligned with seconds 0, 15, 30, 45
        timeUpdateInterval = setInterval(notifyTimeListeners, 15000);
    }, secondsUntilNext15 * 1000);
}

// Stops the global timer
export function stopGlobalTimeUpdates() {
    if (timeUpdateInterval) {
        clearInterval(timeUpdateInterval);
        timeUpdateInterval = null;
    }
}

// Register a listener to receive time updates
export function registerTimeUpdateListener(listener: TimeUpdateListener): () => void {
    timeUpdateListeners.push(listener);
    
    // Start the global timer if it's the first listener
    if (timeUpdateListeners.length === 1) {
        startGlobalTimeUpdates();
    }
    
    // Return function to remove the listener
    return () => {
        const index = timeUpdateListeners.indexOf(listener);
        if (index !== -1) {
            timeUpdateListeners.splice(index, 1);
        }
        
        // Stop the global timer if there are no listeners
        if (timeUpdateListeners.length === 0) {
            stopGlobalTimeUpdates();
        }
    };
}

// Notify all listeners that they must update their times
function notifyTimeListeners() {
    console.log(`Notifying ${timeUpdateListeners.length} components of time update`);
    timeUpdateListeners.forEach(listener => {
        try {
            listener();
        } catch (error) {
            console.error('Error in time listener:', error);
        }
    });
}

// Get a simplified listener string from the server info object
export function getListenerString(serverInfo: Types.ServerInfo): string {
    if (!serverInfo || !serverInfo.config) {
        return 'Invalid server configuration';
    }
    
    const listenerHost = serverInfo.config.listenerHost ? serverInfo.config.listenerHost : serverInfo.config.listenerIp
    var listenerPort = `:${serverInfo.config.listenerPort}`
    if ((serverInfo.config.listenerType === "HTTP" && serverInfo.config.listenerPort === 80)
       || (serverInfo.config.listenerType === "HTTPS" && serverInfo.config.listenerPort === 443)) {
         listenerPort = ""
       }
    return `${serverInfo.config.listenerType.toLowerCase()}://${listenerHost}${listenerPort}`
}

// Function to convert console data to formatted text for display
export const consoleToText = (consoleData: any) => {
  if (!consoleData || consoleData.length === 0) return "";
  
  // Use taskTime or resultTime for sorting
  const sortedData = [...consoleData].sort((a, b) => {
    // Compare dates/times for chronological sorting
    const timeA = a.taskTime || a.resultTime || '';
    const timeB = b.taskTime || b.resultTime || '';
    
    // Compare dates/times for chronological sorting
    return timeA.localeCompare(timeB);
  });
  
  let output = "";
  let lastWasCommand = false;
  
  // Iterate over sorted data and maintain original format
  for (let i = 0; i < sortedData.length; i++) {
    const item = sortedData[i];
    const nextItem = i < sortedData.length - 1 ? sortedData[i + 1] : null;
    
    // Show command if it exists
    if (item.task) {
      // If we come from a previous result, add an extra line break only if there isn't enough space already
      const endsWithMultipleNewlines = output.endsWith('\n\n') || output.endsWith('\r\n\r\n');
      if (!lastWasCommand && i > 0 && !endsWithMultipleNewlines) {
        output += "\n";
      }
      
      output += `[${item.taskTime}] > ${item.taskFriendly}\n`;
      lastWasCommand = true;
    }
    
    // Show result if it exists
    if (item.resultTime) {
      output += `[${item.resultTime}]   ${item.result}\n`;
      lastWasCommand = false;
    }
    // If there is a result but no timestamp
    else if (item.result) {
      output += `${item.result}\n`;
      lastWasCommand = false;
    }
    
    // If we are at the end of a response and the next element is a command,
    // add an extra line break only if the response doesn't already end with multiple breaks
    if (nextItem && nextItem.task && !lastWasCommand) {
      // Check if it already ends with multiple line breaks
      const resultText = item.result || '';
      const endsWithNewlines = resultText.endsWith('\n\n') || 
                              resultText.endsWith('\r\n\r\n') ||
                              output.endsWith('\n\n') ||
                              output.endsWith('\r\n\r\n');
      
      if (!endsWithNewlines) {
        output += "\n";
      }
    }
  }
  
  return output;
}

export function showConnectionError(): void {
    notifications.show({
        id: 'ConnErr',
        autoClose: false,
        color: 'red',
        withCloseButton: false,
        loading: true,
        message: 'Trying to reconnect to Nimhawk server',
        title: "Connection error",
      });
}

export function restoreConnectionError(): void {
    notifications.update({
        id: 'ConnErr',
        autoClose: 3000,
        color: 'teal',
        withCloseButton: true,
        loading: false,
        message: 'Connection to the Nimhawk server was restored',
        title: 'Connection restored',
      });
}

export const nimplantInfo = async (guid: string) => {
  try {
    // Get authentication token
    let token = null;
    if (typeof window !== 'undefined') {
      token = localStorage.getItem('auth_token');
    }

    // Build headers with authentication token
    const headers: Record<string, string> = {
      'Content-Type': 'application/json'
    };

    if (token) {
      headers['Authorization'] = `Bearer ${token}`;
    }

    const response = await fetch(`${SERVER_BASE_URL}/api/nimplants/${guid}`, {
      method: 'GET',
      headers,
      credentials: 'include',
    })

    if (response.ok) {
      const data = await response.json()
      return {
        success: true,
        data,
      }
    } else {
      const errorData = await response.text()
      let errorMessage = `Error obtaining information about the implant (HTTP ${response.status})`;
      
      try {
        const parsedError = JSON.parse(errorData);
        if (parsedError.error || parsedError.message) {
          errorMessage = parsedError.error || parsedError.message;
        }
      } catch (e) {
        // If not JSON, use the response text
        if (errorData) {
          errorMessage = errorData;
        }
      }
      
      return {
        success: false,
        error: errorMessage,
      }
    }
  } catch (error: any) {
    return {
      success: false,
      error: error.message || 'Unknown error',
    }
  }
}