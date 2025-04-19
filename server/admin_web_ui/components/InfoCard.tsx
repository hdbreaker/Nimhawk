import { Paper, Group, Stack } from "@mantine/core"
import { ReactNode } from "react"

type InfoCardType = {
  icon: ReactNode,
  content: ReactNode,
}

// Component for single information card (for server and implant data)
function InfoCard({icon, content, compact = false}: InfoCardType & { compact?: boolean }) {
  return (
    <Paper 
      shadow="sm" 
      p={compact ? "sm" : "md"}
      withBorder
      style={{ 
        height: '100%',
        fontSize: compact ? '0.9rem' : '1rem',
        background: compact ? 'transparent' : 'white'
      }}
    >
      <Stack 
        pl={compact ? 2 : 5} 
        align="flex-start" 
        justify="space-evenly" 
        gap={compact ? "md" : "lg"}
      >
        <Group style={{ color: 'var(--mantine-color-dark-3)' }}>
          {icon}
        </Group>
        <Group style={{ 
          color: 'var(--mantine-color-dark-8)',
          fontSize: '0.9rem',
          flex: 1
        }}>
          {content}
        </Group>
      </Stack>
    </Paper>
  )
}

export default InfoCard