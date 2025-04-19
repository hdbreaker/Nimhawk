import { Dots } from '../components/Dots';
import { FaGithub, FaArrowRight } from 'react-icons/fa';
import { 
  Title, 
  Text, 
  Button, 
  Container, 
  useMantineTheme, 
  Group,
  Box,
  Stack,
  Image,
} from '@mantine/core';
import { useMediaQuery } from '@mantine/hooks';
import TitleBar from '../components/TitleBar';
import type { NextPage } from 'next';
import classes from '../styles/styles.module.css';
import { motion } from 'framer-motion';

const Index: NextPage = () => {
  const largeScreen = useMediaQuery('(min-width: 767px)');
  
  // Define animation variants
  const containerVariants = {
    hidden: { opacity: 0 },
    visible: { 
      opacity: 1,
      transition: {
        when: "beforeChildren",
        staggerChildren: 0.2,
        duration: 0.3
      }
    }
  };

  const itemVariants = {
    hidden: { 
      opacity: 0, 
      y: 20 
    },
    visible: { 
      opacity: 1, 
      y: 0,
      transition: {
        type: "spring",
        stiffness: 100,
        damping: 10
      }
    }
  };

  return (
    <div style={{ 
      height: 'calc(100vh - 70px)',
      position: 'relative',
      backgroundColor: '#FFFFFF',
      marginTop: 0,
      overflow: 'hidden',
      display: 'flex',
      alignItems: 'center',
      justifyContent: 'center',
      borderTop: 'none',
      borderBottom: 'none',
    }}>
      <motion.div
        initial="hidden"
        animate="visible"
        variants={containerVariants}
        style={{ 
          width: '100%',
          height: '100%',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          padding: '2rem',
          backgroundColor: '#FFFFFF',
          borderBottom: 'none'
        }}
      >
        <Stack 
          align="center" 
          justify="center"
          w="100%"
          maw={950}
          mx="auto"
          gap={40}
          style={{
            backgroundColor: '#FFFFFF',
            borderBottom: 'none'
          }}
        >
          {/* Main Logo and Text */}
          <motion.div
            variants={itemVariants}
            whileHover={{ 
              scale: 1.05,
              filter: 'brightness(1.1)',
              transition: { duration: 0.3 }
            }}
          >
            <Image
              src="/nimhawk.png"
              alt="Nimhawk Logo"
              width={180}
              height={180}
              style={{ 
                opacity: 1,
                transition: 'all 0.3s ease'
              }}
            />
          </motion.div>

          <Stack gap="xl" align="center">
            <motion.div variants={itemVariants}>
              <Text 
                style={{
                  color: '#333333',
                  fontSize: largeScreen ? '2.8rem' : '2rem',
                  fontWeight: 300,
                  letterSpacing: '-0.8px',
                  textAlign: 'center',
                  lineHeight: 1.2,
                }}
              >
                First-stage implant for adversarial operations
              </Text>
            </motion.div>

            <motion.div variants={itemVariants}>
              <Text 
                style={{
                  color: '#555555',
                  fontSize: largeScreen ? '1.5rem' : '1.2rem',
                  lineHeight: 1.6,
                  maxWidth: '700px',
                  textAlign: 'center',
                  fontWeight: 300,
                  marginTop: '0.5rem'
                }}
              >
                Powerful, modular, lightweight and efficient command & control framework.
              </Text>
            </motion.div>
          </Stack>
          
          {/* Footer with dynamic version badge */}
          <motion.div variants={itemVariants}>
            <Box
              style={{
                backgroundColor: '#1A1A1A',
                color: 'white',
                padding: '0.35rem 0.8rem',
                borderRadius: '20px',
                display: 'inline-flex',
                alignItems: 'center',
                marginTop: '2rem',
                boxShadow: '0 2px 8px rgba(0,0,0,0.08)',
                marginBottom: '1rem'
              }}
            >
              <Text
                size="xs"
                fw={500}
                style={{
                  letterSpacing: '0.5px',
                  fontSize: '0.75rem'
                }}
              >
                VERSION {'1.0'}
              </Text>
            </Box>
          </motion.div>
        </Stack>
      </motion.div>
      
      <style jsx global>{`
        .mantine-AppShell-main {
          background-color: #FFFFFF !important;
          border-bottom: none !important;
        }
        
        .mantine-Box-root {
          border-bottom: none !important;
        }
        
        * {
          border-bottom: none !important;
          background-color: transparent;
        }
        
        div[style*="height: calc(100vh - 70px)"] {
          background-color: #FFFFFF !important;
          border-bottom: none !important;
        }
      `}</style>
    </div>
  );
};

export default Index;
