import { Group, Paper, Title } from "@mantine/core";
import React from "react";

type TitleBar = {
  title: string,
  icon: React.ReactNode,
  noBorder?: boolean,
}

// Simple title bar to show as page header
function TitleBar({ title, icon, noBorder = false }: TitleBar) {
  return (
    <Paper 
      style={{ 
        height: '70px',
        backgroundColor: '#FFFFFF',
        display: 'flex',
        alignItems: 'center',
        padding: '0 2rem',
        borderBottom: 'none',
        width: '100%'
      }}
    >
      <Group gap="md" style={{ flex: 1 }}>
        {icon} 
        <Title order={1} style={{ 
          fontSize: '1.5rem',
          color: 'var(--mantine-color-dark-8)',
          fontWeight: 600
        }}>
          {title}
        </Title>
      </Group>
    </Paper>
  )
}

export default TitleBar