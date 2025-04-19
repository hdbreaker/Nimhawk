import React, { useState, useEffect } from 'react';
import { useRouter } from 'next/router';
import axios from 'axios';
import { SERVER_BASE_URL } from '../config';

interface AuthWrapperProps {
  children: React.ReactNode;
}

const AuthWrapper: React.FC<AuthWrapperProps> = ({ children }) => {
  const [isAuthenticated, setIsAuthenticated] = useState<boolean | null>(null);
  const router = useRouter();

  // Public routes that don't require authentication
  const publicRoutes = ['/login'];

  useEffect(() => {
    const checkAuth = async () => {
      try {
        // Check if there's a token
        const token = localStorage.getItem('auth_token');
        if (!token) {
          if (!publicRoutes.includes(router.pathname)) {
            router.push('/login');
          }
          setIsAuthenticated(false);
          return;
        }

        // Verify token with backend
        try {
          console.log('Token found in localStorage:', token ? `${token.substring(0, 10)}...` : 'none');
          
          // Ensure the token is sent correctly
          const response = await axios.get(`${SERVER_BASE_URL}/api/auth/verify`, {
            headers: {
              'Content-Type': 'application/json',
              'Authorization': `Bearer ${token}` // Ensure correct format
            },
            withCredentials: true // To send cookies
          });

          console.log('Verify response:', response.status, response.data);

          if (response.data && response.data.authenticated === true) {
            console.log('Verification successful:', response.data);
            setIsAuthenticated(true);
            if (router.pathname === '/login') {
              router.push('/');
            }
          } else {
            console.error('Token valid but not authenticated:', response.data);
            localStorage.removeItem('auth_token');
            setIsAuthenticated(false);
            if (!publicRoutes.includes(router.pathname)) {
              router.push('/login');
            }
          }
        } catch (error: any) {
          console.error('Error verifying authentication:', error);
          console.error('Error details:', error.response ? {
            status: error.response.status,
            data: error.response.data,
            headers: error.response.headers
          } : 'No response');
          
          // Clear invalid token
          localStorage.removeItem('auth_token');
          setIsAuthenticated(false);
          if (!publicRoutes.includes(router.pathname)) {
            router.push('/login');
          }
        }
      } catch (error) {
        console.error('Error verifying authentication:', error);
        // Clear invalid token
        localStorage.removeItem('auth_token');
        setIsAuthenticated(false);
        if (!publicRoutes.includes(router.pathname)) {
          router.push('/login');
        }
      }
    };

    checkAuth();
  }, [router.pathname, publicRoutes, router]);

  // Show loading or nothing while verifying authentication
  if (isAuthenticated === null) {
    return null; // Don't show anything while verifying
  }

  // If it's a public route or the user is authenticated, show the content
  if (publicRoutes.includes(router.pathname) || isAuthenticated) {
    return <>{children}</>;
  }

  // By default, don't show anything (this prevents protected content from being
  // momentarily visible before redirection)
  return null;
};

export default AuthWrapper; 