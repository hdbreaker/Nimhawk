import React, { useState } from "react";
import Head from 'next/head';
import { AppShell, Burger, useMantineTheme, Image, Badge, Space, Box, Text } from "@mantine/core";
import { useMediaQuery, useDisclosure } from "@mantine/hooks";
import NavbarContents from "./NavbarContents";
import TitleBar from './TitleBar';
import axios from 'axios';
import { useRouter } from 'next/router';
import { SERVER_BASE_URL } from '../config';

// Basic component for highlighted text
export function Highlight({ children }: { children: React.ReactNode }) {
  return (
    <span style={{
      fontWeight: 700,
      display: 'inline'
    }}>
      {children}
    </span>
  )
}

// Main layout component
export function MainLayout({ children, className }: React.PropsWithChildren<{ className?: string }>) {
  const theme = useMantineTheme();
  const router = useRouter();
  // Initialize state as true so it is collapsed by default
  const [collapsed, setCollapsed] = useState(true);

  // Sidebar width according to its state
  const sidebarWidth = collapsed ? 70 : 250;

  const handleLogout = async () => {
    try {
      // Get token from localStorage
      const token = localStorage.getItem('auth_token');
      
      // Call the logout endpoint
      await axios.post(`${SERVER_BASE_URL}/api/auth/logout`, {}, {
        headers: {
          'Authorization': `Bearer ${token}`
        }
      });
      
      // Remove token from localStorage
      localStorage.removeItem('auth_token');
      
      // Redirect to login
      router.push('/login');
    } catch (error) {
      console.error('Error logging out:', error);
      // In case of error, try to clean up anyway
      localStorage.removeItem('auth_token');
      router.push('/login');
    }
  };

  return (
    <>
      {/* Header information (static for all pages) */}
      <Head>
        <title key="title">Nimhawk</title>
        <link rel="icon" type="image/svg+xml" href="/favicon.png" />
        <link rel="icon" type="image/png" href="/favicon.png" />
      </Head>

      {/* Main layout (header-sidebar-content) is managed via AppShell */}
      <AppShell
        header={{ height: 70 }}
        navbar={{
          width: sidebarWidth,
          breakpoint: 'sm',
          collapsed: { mobile: collapsed }
        }}
        padding={0}
        layout="alt"
        styles={{
          main: {
            background: theme.colors.gray[0],
            padding: 0,
            marginLeft: sidebarWidth,
            width: `calc(100% - ${sidebarWidth}px)`,
            transition: 'margin-left 0.3s ease, width 0.3s ease'
          },
          navbar: {
            width: sidebarWidth,
            minWidth: sidebarWidth,
            transition: 'width 0.3s ease, min-width 0.3s ease',
            zIndex: 200,
            borderTop: 'none',
            borderLeft: 'none',
            borderRight: 'none',
            margin: 0
          },
          header: {
            borderBottom: '1px solid var(--mantine-color-gray-2)',
            zIndex: 3,
            backgroundColor: '#FFFFFF',
            borderTop: 'none',
            marginTop: 0,
            paddingTop: 0
          },
          root: {
            overflow: 'hidden'
          }
        }}
      >
        <AppShell.Header style={{ 
          display: 'flex', 
          justifyContent: 'space-between',
          backgroundColor: '#FFFFFF',
          marginTop: 0,
          borderTop: 'none',
          
        }}>
          <Burger
            opened={!collapsed}
            onClick={() => setCollapsed(!collapsed)}
            hiddenFrom="sm"
            size="sm"
            color={theme.colors.gray[6]}
            p="xl"
          />

          <div style={{ display: 'flex', alignItems: 'center', width: '380px', height: '100%' }}>
            <Image alt="Logo" m="lg" ml="xs" mr="xs" src='/nimhawk_header.png' fit='contain' height={33} style={{ paddingLeft: '3px' }} />
          </div>
        </AppShell.Header>

        <AppShell.Navbar p={0} style={{ 
          borderTop: 'none',
          borderLeft: 'none',
          borderRight: 'none',
          margin: 0
        }}>
          <NavbarContents collapsed={collapsed} setCollapsed={setCollapsed} />
        </AppShell.Navbar>

        <AppShell.Main>
          <Box className={className}>
            {children}
          </Box>
        </AppShell.Main>
      </AppShell>

      <style jsx global>{`
        html, body {
          margin: 0;
          padding: 0;
          overflow: hidden;
        }
        
        .mantine-AppShell-root {
          overflow: hidden;
        }
        
        .mantine-AppShell-navbar {
          border-top: none !important;
          margin-top: 0 !important;
        }
        
        .mantine-AppShell-header {
          border-top: none !important;
          margin-top: 0 !important;
        }
      `}</style>
    </>
  )
}

export default MainLayout;