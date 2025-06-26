// Centralized version management for Nimhawk
// This reads the version from package.json to maintain a single source of truth

import packageJson from './package.json';

export const NIMHAWK_VERSION = packageJson.version;

// Helper function to get version string
export const getVersion = () => NIMHAWK_VERSION;

// Helper function to get display version (always shows full version)
export const getDisplayVersion = () => NIMHAWK_VERSION; 