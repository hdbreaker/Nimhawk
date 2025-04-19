/**
 * API utilities for centralized authentication and error handling
 */

import { endpoints } from './nimplant';

/**
 * Common fetch function that handles authentication and error states
 */
export const authenticatedFetch = async (url: string, options: RequestInit = {}) => {
  // Get token from localStorage
  const token = localStorage.getItem('auth_token');

  // Prepare headers with authorization if token exists
  const headers = {
    'Content-Type': 'application/json',
    ...options.headers,
    ...(token ? { 'Authorization': `Bearer ${token}` } : {})
  };

  // Execute the fetch with combined options
  const response = await fetch(url, {
    ...options,
    headers,
    credentials: 'include'
  });

  // Debug information
  console.log(`API call to ${url} - Status: ${response.status}`);

  // Handle authentication errors consistently
  if (response.status === 401) {
    console.error(`Authentication failed (401) for ${url}`);
    localStorage.removeItem('auth_token');
    window.location.href = '/login';
    throw new Error('Authentication required');
  }

  // For other errors, provide details
  if (!response.ok) {
    const errorText = await response.text().catch(() => 'No error details');
    throw new Error(`API error ${response.status}: ${errorText}`);
  }

  // For successful responses that need JSON parsing
  if (response.headers.get('content-type')?.includes('application/json')) {
    return response.json();
  }

  // For other types, return the response directly
  return response;
};

/**
 * Central fetcher for SWR hooks
 */
export const swrFetcher = (url: string) => authenticatedFetch(url).then(res => res);

/**
 * General API functions
 */
export const api = {
  // GET requests
  get: (url: string) => authenticatedFetch(url),
  
  // POST requests with JSON body
  post: (url: string, data: any) => authenticatedFetch(url, {
    method: 'POST',
    body: JSON.stringify(data)
  }),
  
  // PUT requests with JSON body
  put: (url: string, data: any) => authenticatedFetch(url, {
    method: 'PUT',
    body: JSON.stringify(data)
  }),
  
  // DELETE requests
  delete: (url: string) => authenticatedFetch(url, {
    method: 'DELETE'
  }),
  
  // File upload with FormData
  upload: (url: string, formData: FormData) => {
    const token = localStorage.getItem('auth_token');
    
    return fetch(url, {
      method: 'POST',
      headers: token ? { 'Authorization': `Bearer ${token}` } : undefined,
      body: formData,
      credentials: 'include'
    }).then(response => {
      if (response.status === 401) {
        localStorage.removeItem('auth_token');
        window.location.href = '/login';
        throw new Error('Authentication required');
      }
      
      if (!response.ok) {
        throw new Error(`Upload failed with status ${response.status}`);
      }
      
      return response.json();
    });
  }
};

export default api; 