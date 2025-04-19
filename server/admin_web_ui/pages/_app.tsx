import '../styles/global.css'
import '@mantine/core/styles.css';
import '@mantine/notifications/styles.css';

import { AppProps } from 'next/app';
import { useRouter } from 'next/router';
import AuthWrapper from '../components/AuthWrapper';
import { MantineProvider, createTheme } from '@mantine/core';
import { Notifications } from '@mantine/notifications';
import MainLayout from '../components/MainLayout';
import axios from 'axios';
import { useEffect } from 'react';
import { SERVER_BASE_URL } from '../config';

// Global axios configuration
axios.defaults.withCredentials = true; // Critical for handling cookies between domains

// Function to configure axios with the current tokens
const configureAxios = () => {
  const token = localStorage.getItem('auth_token');
  if (token) {
    axios.defaults.headers.common['Authorization'] = `Bearer ${token}`;
    console.log('Global axios configured with token:', token.substring(0, 10) + '...');
  } else {
    delete axios.defaults.headers.common['Authorization'];
    console.log('Global axios configured without token');
  }
};

// Define the custom Mantine theme
const theme = createTheme({
  fontFamily: 'Inter, sans-serif',
  fontFamilyMonospace: 'Roboto Mono, monospace',
  headings: { 
    fontFamily: 'Inter, sans-serif',
    fontWeight: '700'
  },
  colors: {
    dark: [
      '#FFFFFF',
      '#F5F5F5',
      '#E5E5E5',
      '#D4D4D4',
      '#A3A3A3',
      '#737373',
      '#525252',
      '#404040',
      '#262626',
      '#171717',
    ],
  },
  primaryColor: 'dark',
  white: '#FFFFFF',
  black: '#000000',
  components: {
    Paper: {
      styles: {
        root: {
          backgroundColor: '#FFFFFF'
        }
      }
    }
  }
});

export default function MyApp(props: AppProps) {
  const { Component, pageProps } = props;
  const router = useRouter();
  
  // Configure axios on app initialization and token changes
  useEffect(() => {
    configureAxios();
    
    // Also set up periodic checks to ensure token is current
    const intervalId = setInterval(() => {
      configureAxios();
    }, 60000); // Check every minute
    
    return () => clearInterval(intervalId);
  }, []);
  
  // Determine if MainLayout should be shown based on the route
  const shouldUseMainLayout = !router.pathname.includes('/login');

  return (
    <MantineProvider theme={theme}>
      <Notifications position="top-right" />
      <AuthWrapper>
        {shouldUseMainLayout ? (
          <MainLayout>
            <Component {...pageProps} />
          </MainLayout>
        ) : (
          <Component {...pageProps} />
        )}
      </AuthWrapper>
    </MantineProvider>
  );
}
