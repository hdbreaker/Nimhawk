import { Box, Center, Group, Image, AppShell, Text, UnstyledButton, Stack } from "@mantine/core";
import { FaHome, FaServer, FaLaptopCode, FaDownload, FaBars } from 'react-icons/fa'
import { useMediaQuery } from "@mantine/hooks";
import Link from "next/link";
import React from "react";
import classes from '../styles/buttonstyles.module.css';

import { useRouter } from 'next/router'

interface MainLinkProps {
  icon: React.ReactNode;
  label: string;
  target: string;
  active: boolean;
  collapsed?: boolean;
}

// Component for single navigation items
function NavItem({ icon, label, target, active, collapsed }: MainLinkProps) {
    const largeScreen = useMediaQuery('(min-width: 1200px)');
    return (
    <Link href={target} passHref style={{ textDecoration: 'none', color: 'inherit' }}>
      <UnstyledButton
        className={`${classes.button} ${active ? classes.buttonActive : classes.buttonInactive}`}
        style={{ padding: '0.5rem' }}
      >
        <Group>
          {icon} {!collapsed && <Text size={largeScreen ? 'xl' : 'lg'}>{label}</Text>}
        </Group>
      </UnstyledButton>
    </Link>
  );
}

interface NavbarContentsProps {
  collapsed: boolean;
  setCollapsed: (collapsed: boolean) => void;
}

// Construct the navbar
function NavbarContents({ collapsed, setCollapsed }: NavbarContentsProps) {
  const currentPath = useRouter().pathname

  const toggleCollapsed = () => {
    setCollapsed(!collapsed);
  };

  return (
    <Stack 
      h="100%" 
      justify="space-between" 
      p={collapsed ? "xs" : "md"}
      style={{ 
        backgroundColor: '#1A1A1A',
        color: '#FFFFFF',
        transition: 'padding 0.3s ease',
        margin: 0,
        borderTop: 'none',
        borderBottom: 'none',
        borderLeft: 'none',
        borderRight: 'none'
      }}
    >
      <Stack gap="xs" mt={0} pt={0}>
        <NavItem 
          icon={<FaHome size='1.2em' />} 
          label="Home" 
          target='/' 
          active={currentPath === '/'} 
          collapsed={collapsed}
        />
        <NavItem 
          icon={<FaServer size='1.2em' />} 
          label="Server" 
          target='/server' 
          active={currentPath === '/server'} 
          collapsed={collapsed}
        />
        <NavItem 
          icon={<FaLaptopCode size='1.2em' />} 
          label="Implants" 
          target='/implants' 
          active={currentPath.startsWith('/implants')} 
          collapsed={collapsed}
        />
        <NavItem 
          icon={<FaDownload size='1.2em' />} 
          label="Downloads" 
          target='/downloads' 
          active={currentPath === '/downloads'} 
          collapsed={collapsed}
        />
      </Stack>

      <Box py="md">
        <UnstyledButton 
          onClick={toggleCollapsed}
          style={{ 
            width: '100%', 
            cursor: 'pointer',
            transition: 'all 0.3s ease',
            '&:hover': {
              opacity: 0.8
            }
          }}
        >
          <Center>
            {collapsed ? (
              <FaBars size={24} color="white" />
            ) : (
              <Image 
                alt='Logo' 
                src='/nimhawk.svg' 
                h={40} 
                style={{ filter: 'brightness(0) invert(1)' }} 
              />
            )}
          </Center>
        </UnstyledButton>
      </Box>
    </Stack>
  )
}

export default NavbarContents