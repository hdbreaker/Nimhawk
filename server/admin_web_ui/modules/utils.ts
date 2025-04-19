/**
 * Utility functions for Nimhawk frontend
 */

/**
 * Validates if a string is a valid GUID
 * 
 * @param guid - The string to check
 * @returns true if the string is a valid GUID, false otherwise
 */
export function isValidGuid(guid: string | null | undefined): boolean {
  // Check if null, undefined or empty string
  if (!guid) {
    return false;
  }
  
  // Check if it's a string
  if (typeof guid !== 'string') {
    return false;
  }
  
  // Check for valid length and no prohibited characters
  // This is a basic validation - a more strict GUID validation could be implemented
  // with a regex pattern if needed
  if (guid.length < 3 || guid.length > 50) {
    return false;
  }
  
  // Ensure there are no slashes or spaces (basic security check)
  if (guid.includes('/') || guid.includes('\\') || guid.includes(' ')) {
    return false;
  }
  
  return true;
}

// Add other utility functions here as needed 