/**
 * API utilities for centralized authentication and error handling
 */

import axios, { AxiosRequestConfig, AxiosResponse } from 'axios';
import { notifications } from '@mantine/notifications';
import { SERVER_BASE_URL } from '../config';

// Create a pre-configured axios instance
const axiosInstance = axios.create({
  baseURL: SERVER_BASE_URL,
  withCredentials: true, // Crucial for handling cookies correctly
  timeout: 10000, // 10 second timeout
  headers: {
    'Content-Type': 'application/json'
  }
});

// Add request interceptor to include the auth token in headers
axiosInstance.interceptors.request.use(config => {
  const token = localStorage.getItem('auth_token');
  if (token) {
    config.headers['Authorization'] = `Bearer ${token}`;
  }
  return config;
}, error => {
  return Promise.reject(error);
});

// Add response interceptor to handle auth errors and network issues
axiosInstance.interceptors.response.use(
  response => response,
  error => {
    // Handle network errors (server not reachable)
    if (error.code === 'ECONNREFUSED' || error.code === 'ERR_NETWORK' || !error.response) {
      console.error('Network error - server not reachable:', error.message);
      
      // Show user-friendly notification
      notifications.show({
        title: 'Sin conexión con el servidor',
        message: 'No se puede conectar al servidor Team Server. Verifique que esté ejecutándose.',
        color: 'red',
        autoClose: 5000,
      });
      
      return Promise.reject(new Error('SERVER_UNAVAILABLE'));
    }
    
    // Handle timeout errors
    if (error.code === 'ECONNABORTED') {
      console.error('Request timeout:', error.message);
      
      notifications.show({
        title: 'Tiempo de espera agotado',
        message: 'El servidor tardó demasiado en responder. Intente nuevamente.',
        color: 'orange',
        autoClose: 5000,
      });
      
      return Promise.reject(new Error('REQUEST_TIMEOUT'));
    }
    
    // Handle 401 errors (authentication failure)
    if (error.response && error.response.status === 401) {
      console.error('Authentication failed (401):', error.config.url);
      localStorage.removeItem('auth_token');
      
      // Only redirect if we're not already on the login page
      if (!window.location.pathname.includes('login')) {
        console.log('Redirecting to login page from:', window.location.pathname);
        window.location.href = '/login';
      }
    }
    
    // Handle other HTTP errors
    if (error.response && error.response.status >= 500) {
      notifications.show({
        title: 'Error del servidor',
        message: 'El servidor encontró un error interno. Intente nuevamente.',
        color: 'red',
        autoClose: 5000,
      });
    }
    
    return Promise.reject(error);
  }
);

/**
 * Centralized API functions
 */
export const api = {
  // GET requests
  get: <T = any>(url: string, config?: AxiosRequestConfig): Promise<T> => {
    console.log(`Making GET request to ${url}`);
    return axiosInstance.get(url, config).then(response => response.data);
  },
  
  // POST requests with JSON body
  post: <T = any>(url: string, data?: any, config?: AxiosRequestConfig): Promise<T> => {
    console.log(`Making POST request to ${url}`);
    return axiosInstance.post(url, data, config).then(response => response.data);
  },
  
  // PUT requests with JSON body
  put: <T = any>(url: string, data?: any, config?: AxiosRequestConfig): Promise<T> => {
    return axiosInstance.put(url, data, config).then(response => response.data);
  },
  
  // DELETE requests
  delete: <T = any>(url: string, config?: AxiosRequestConfig): Promise<T> => {
    return axiosInstance.delete(url, config).then(response => response.data);
  },
  
  // File upload with FormData
  upload: <T = any>(url: string, formData: FormData, config?: AxiosRequestConfig): Promise<T> => {
    console.log(`Making file upload request to ${url}`);
    return axiosInstance.post(url, formData, {
      ...config,
      headers: {
        ...config?.headers,
        'Content-Type': 'multipart/form-data'
      }
    }).then(response => response.data);
  }
};

// For SWR hooks - with better error handling
export const swrFetcher = <T = any>(url: string) => {
  return api.get<T>(url).catch(error => {
    // For SWR, we want to fail silently on network errors to avoid infinite retries
    if (error.message === 'SERVER_UNAVAILABLE' || error.message === 'REQUEST_TIMEOUT') {
      throw error; // SWR will handle retries
    }
    throw error;
  });
};

export default api; 