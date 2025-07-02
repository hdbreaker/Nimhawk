import React, { useState, useEffect, useCallback } from 'react';
import { Container, Title, Text, Card, Group, Button, Alert, LoadingOverlay, Stack } from '@mantine/core';
import { FaSyncAlt, FaExclamationTriangle, FaNetworkWired } from 'react-icons/fa';
import ReactFlow, {
  useNodesState,
  useEdgesState,
  addEdge,
  Connection,
  Edge,
  Node,
  MarkerType,
  Handle,
  Position,
} from 'reactflow';
import dagre from 'dagre';

import 'reactflow/dist/style.css';

import AuthWrapper from '../components/AuthWrapper';
import MainLayout from '../components/MainLayout';
import { api } from '../modules/apiFetcher';

interface TopologyData {
  id: string;
  nimplant_guid: string;
  topology_json: any;
  last_update: string;
  relay_role: string;
}

interface NimplantData {
  guid: string;
  hostname: string;
  username: string;
  ip_external: string;
  ip_internal: string;
  os_build: string;
  process_name: string;
  relay_role: string;
  active: boolean;
  late: boolean;
}

// Hierarchical tree data structure
interface TreeNode {
  id: string;
  type: string;
  status: 'online' | 'late' | 'disconnected';
  ip: string;
  os: string;
  hostname: string;
  children: TreeNode[];
}

// Helper function to get OS icon
const getOSIcon = (os: string) => {
  const osLower = os.toLowerCase();
  if (osLower.includes('windows') || osLower.includes('win')) return '🪟';
  if (osLower.includes('linux') || osLower.includes('ubuntu') || osLower.includes('debian')) return '🐧';
  if (osLower.includes('darwin') || osLower.includes('macos') || osLower.includes('mac')) return '🍎';
  if (osLower.includes('android')) return '🤖';
  if (osLower.includes('ios')) return '📱';
  return '💻';
};

// Helper function to get status color (Nimhawk official colors)
const getStatusColor = (status: string) => {
  switch (status) {
    case 'online': return '#00FF88';    // Nimhawk green
    case 'late': return '#FFB300';      // Nimhawk yellow
    case 'disconnected': return '#FF3B30'; // Nimhawk red
    default: return '#6b7280';
  }
};

// Helper function to create hierarchical tree node style (Refined Nimhawk style)
const createTreeNodeStyle = (status: string, isC2Server = false) => {
  const statusColor = getStatusColor(status);
  
  return {
    background: '#0E1A26',  // Refined background color
    border: `2px solid ${statusColor}`,
    borderRadius: '10px',
    padding: '16px',
    width: '280px',
    height: '180px',
    fontFamily: 'system-ui, -apple-system, sans-serif',
    color: '#ffffff',
    boxShadow: `0 4px 16px rgba(0, 0, 0, 0.4)`,
    position: 'relative' as const,
    display: 'flex',
    flexDirection: 'column' as const,
    justifyContent: 'flex-start',
  };
};

// Build tree structure from flat nimplants data
const buildTreeStructure = (nimplants: NimplantData[]): TreeNode => {
  // Create the root C2 node
  const c2Root: TreeNode = {
    id: 'c2-server',
    type: 'C2 Server',
    status: 'online',
    ip: 'Command & Control',
    os: 'server',
    hostname: 'C2 SERVER',
    children: []
  };

  // Convert nimplants to tree nodes
  const treeNodes: TreeNode[] = nimplants.map(nimplant => ({
    id: nimplant.guid,
    type: nimplant.relay_role || 'STANDARD',
    status: nimplant.active ? (nimplant.late ? 'late' : 'online') : 'disconnected',
    ip: nimplant.ip_internal || 'No IP',
    os: nimplant.os_build || 'Unknown',
    hostname: nimplant.hostname || `Agent-${nimplant.guid.substring(0, 8)}`,
    children: []
  }));

  // Sort function: ONLINE first, then LATE, then DISCONNECTED
  const sortByStatus = (a: TreeNode, b: TreeNode) => {
    const statusOrder = { 'online': 0, 'late': 1, 'disconnected': 2 };
    return statusOrder[a.status] - statusOrder[b.status];
  };

  // Organize by hierarchy: Relay Servers -> Standard/Clients -> others
  const relayServers = treeNodes.filter(n => n.type === 'RELAY_SERVER').sort(sortByStatus);
  const relayClients = treeNodes.filter(n => n.type === 'RELAY_CLIENT').sort(sortByStatus);
  const relayHybrids = treeNodes.filter(n => n.type === 'RELAY_HYBRID').sort(sortByStatus);
  const standardAgents = treeNodes.filter(n => n.type === 'STANDARD').sort(sortByStatus);

  // Create hierarchy: C2 -> Relay Servers -> [Standard, Clients, Hybrids]
  if (relayServers.length > 0) {
    // Relay servers connect directly to C2
    c2Root.children = relayServers;
    
    // Distribute other agents among relay servers, maintaining sort order
    const otherAgents = [...standardAgents, ...relayClients, ...relayHybrids];
    otherAgents.forEach((agent, index) => {
      const serverIndex = index % relayServers.length;
      relayServers[serverIndex].children.push(agent);
    });
    
    // Sort children of each relay server by status
    relayServers.forEach(server => {
      server.children.sort(sortByStatus);
    });
  } else {
    // No relay servers, all agents connect directly to C2 (already sorted)
    c2Root.children = treeNodes.sort(sortByStatus);
  }

  return c2Root;
};

// Custom node component with proper handles
const CustomNode = ({ data }: { data: any }) => {
  return (
    <div style={data.style}>
      {/* Left handle for incoming connections */}
      <Handle
        type="target"
        position={Position.Left}
        style={{
          background: '#555',
          width: '8px',
          height: '8px',
          border: '1px solid #fff',
        }}
      />
      
      {/* Node content */}
      {data.content}
      
      {/* Right handle for outgoing connections */}
      <Handle
        type="source"
        position={Position.Right}
        style={{
          background: '#555',
          width: '8px',
          height: '8px',
          border: '1px solid #fff',
        }}
      />
    </div>
  );
};

// Register custom node types
const nodeTypes = {
  customNode: CustomNode,
};

// Auto-layout function using dagre
const getLayoutedElements = (nodes: Node[], edges: Edge[], direction = 'LR') => {
  const dagreGraph = new dagre.graphlib.Graph();
  dagreGraph.setDefaultEdgeLabel(() => ({}));
  
  const nodeWidth = 280;
  const nodeHeight = 200;
  
  dagreGraph.setGraph({ 
    rankdir: direction,
    nodesep: 300,    // Much more horizontal spacing between nodes in same rank
    ranksep: 500,    // Much more vertical spacing between different ranks/levels
    marginx: 100,
    marginy: 100,
  });

  nodes.forEach((node) => {
    dagreGraph.setNode(node.id, { width: nodeWidth, height: nodeHeight });
  });

  edges.forEach((edge) => {
    dagreGraph.setEdge(edge.source, edge.target);
  });

  dagre.layout(dagreGraph);

  nodes.forEach((node) => {
    const nodeWithPosition = dagreGraph.node(node.id);
    node.targetPosition = Position.Left;
    node.sourcePosition = Position.Right;

    // Dagre gives center coordinates, we need top-left
    node.position = {
      x: nodeWithPosition.x - nodeWidth / 2,
      y: nodeWithPosition.y - nodeHeight / 2,
    };

    return node;
  });

  return { nodes, edges };
};



function TopologyGraph({ topologies, nimplants }: { topologies: TopologyData[], nimplants: NimplantData[] }) {
  const [nodes, setNodes, onNodesChange] = useNodesState([]);
  const [edges, setEdges, onEdgesChange] = useEdgesState([]);

  const onConnect = useCallback(
    (params: Edge | Connection) => setEdges((eds) => addEdge(params, eds)),
    [setEdges]
  );

  useEffect(() => {
    if (!nimplants || nimplants.length === 0) {
      // Show just the C2 node when no nimplants
      const c2Node: Node = {
        id: 'c2-server',
        type: 'customNode',
        position: { x: 250, y: 250 },
        data: { 
          style: createTreeNodeStyle('online', true),
          content: (
            <div style={{ display: 'flex', flexDirection: 'column', height: '100%' }}>
              <div style={{ 
                display: 'flex',
                alignItems: 'center',
                gap: '12px',
                marginBottom: '8px'
              }}>
                <div style={{ 
                  width: '32px', 
                  height: '32px',
                  background: 'url(/nimhawk-head.png) center/contain no-repeat',
                  flexShrink: 0
                }} />
                <div style={{ flex: 1 }}>
                  <div style={{ 
                    fontSize: '16px', 
                    fontWeight: 'bold',
                    color: '#ffffff',
                    marginBottom: '2px'
                  }}>
                    Nimhawk C2
                  </div>
                  <div style={{ 
                    fontSize: '12px', 
                    color: '#AAAAAA'
                  }}>
                    Command & Control
                  </div>
                </div>
              </div>
              
              <div style={{ 
                fontSize: '12px', 
                color: '#666666',
                fontFamily: 'monospace',
                marginBottom: '8px'
              }}>
                10.0.0.1
              </div>
              
              <div style={{
                display: 'inline-block',
                background: 'rgba(0, 255, 136, 0.1)',
                border: '1px solid #00FF88',
                color: '#00FF88',
                padding: '4px 8px',
                borderRadius: '6px',
                fontSize: '10px',
                fontWeight: '600',
                textTransform: 'uppercase' as const,
                alignSelf: 'flex-start'
              }}>
                ONLINE
              </div>
            </div>
          )
        },
        draggable: true,
      };
      
      setNodes([c2Node]);
      setEdges([]);
      return;
    }

    // Build tree structure
    const tree = buildTreeStructure(nimplants);
    
    const newNodes: Node[] = [];
    const newEdges: Edge[] = [];

    // Create nodes for the tree
    const createTreeNode = (treeNode: TreeNode): Node => {
      const statusColor = getStatusColor(treeNode.status);
      const osIcon = getOSIcon(treeNode.os);
      
      // Special styling for C2 server
      if (treeNode.id === 'c2-server') {
        return {
          id: treeNode.id,
          type: 'customNode',
          position: { x: 0, y: 0 }, // Will be set by dagre layout
          data: {
            style: createTreeNodeStyle(treeNode.status, true),
            content: (
              <div style={{ display: 'flex', flexDirection: 'column', height: '100%' }}>
                <div style={{ 
                  display: 'flex',
                  alignItems: 'center',
                  gap: '12px',
                  marginBottom: '8px'
                }}>
                  <div style={{ 
                    width: '32px', 
                    height: '32px',
                    background: 'url(/nimhawk-head.png) center/contain no-repeat',
                    flexShrink: 0
                  }} />
                  <div style={{ flex: 1 }}>
                    <div style={{ 
                      fontSize: '16px', 
                      fontWeight: 'bold',
                      color: '#ffffff',
                      marginBottom: '2px'
                    }}>
                      Nimhawk C2
                    </div>
                    <div style={{ 
                      fontSize: '12px', 
                      color: '#AAAAAA'
                    }}>
                      Command & Control
                    </div>
                  </div>
                </div>
                
                <div style={{ 
                  fontSize: '12px', 
                  color: '#AAAAAA',
                  fontFamily: 'monospace',
                  marginBottom: '8px'
                }}>
                  10.0.0.1
                </div>
                
                <div style={{
                  display: 'inline-block',
                  background: `rgba(${statusColor === '#00FF88' ? '0, 255, 136' : statusColor === '#FFB300' ? '255, 179, 0' : '255, 59, 48'}, 0.1)`,
                  border: `1px solid ${statusColor}`,
                  color: statusColor,
                  padding: '4px 8px',
                  borderRadius: '6px',
                  fontSize: '10px',
                  fontWeight: '600',
                  textTransform: 'uppercase' as const,
                  alignSelf: 'flex-start'
                }}>
                  {treeNode.status.toUpperCase()}
                </div>
              </div>
            )
          },
          draggable: true,
        };
      }

      // Regular agent nodes - Nimhawk style
      return {
        id: treeNode.id,
        type: 'customNode',
        position: { x: 0, y: 0 }, // Will be set by dagre layout
        data: {
          style: createTreeNodeStyle(treeNode.status),
          content: (
            <div style={{ display: 'flex', flexDirection: 'column', height: '100%' }}>
              <div style={{ 
                display: 'flex',
                alignItems: 'center',
                gap: '12px',
                marginBottom: '8px'
              }}>
                <div style={{ fontSize: '24px' }}>{osIcon}</div>
                <div style={{ flex: 1 }}>
                  <div style={{ 
                    fontSize: '14px', 
                    fontWeight: 'bold',
                    color: '#ffffff',
                    marginBottom: '2px'
                  }}>
                    {treeNode.hostname}
                  </div>
                  <div style={{ 
                    fontSize: '12px', 
                    color: '#AAAAAA',
                    fontFamily: 'monospace'
                  }}>
                    ID: {treeNode.id.substring(0, 8).toUpperCase()}
                  </div>
                </div>
              </div>
              
              <div style={{ 
                fontSize: '12px', 
                color: '#AAAAAA',
                textTransform: 'uppercase' as const,
                marginBottom: '8px'
              }}>
                {treeNode.type.replace('_', ' ')}
              </div>
              
              <div style={{ 
                fontSize: '12px', 
                color: '#AAAAAA',
                fontFamily: 'monospace',
                marginBottom: '8px'
              }}>
                {treeNode.ip}
              </div>
              
              <div style={{
                display: 'inline-block',
                background: `rgba(${statusColor === '#00FF88' ? '0, 255, 136' : statusColor === '#FFB300' ? '255, 179, 0' : '255, 59, 48'}, 0.1)`,
                border: `1px solid ${statusColor}`,
                color: statusColor,
                padding: '4px 8px',
                borderRadius: '6px',
                fontSize: '10px',
                fontWeight: '600',
                textTransform: 'uppercase' as const,
                alignSelf: 'flex-start'
              }}>
                {treeNode.status.toUpperCase()}
              </div>
            </div>
          )
        },
        draggable: true,
      };
    };

    // Traverse tree and create nodes
    const traverse = (node: TreeNode) => {
      newNodes.push(createTreeNode(node));
      
      // Create edges to children (connections flow left to right - Nimhawk style)
      node.children.forEach(child => {
        const childStatusColor = getStatusColor(child.status);
        newEdges.push({
          id: `${node.id}-to-${child.id}`,
          source: node.id,
          target: child.id,
          type: 'smoothstep',
          animated: false,
          style: { 
            stroke: childStatusColor,
            strokeWidth: 3,
            strokeDasharray: '8,4', // Always dotted as requested
          },
          // No arrow markers as requested
        });
        
        traverse(child);
      });
    };

    traverse(tree);
    
    // Apply simple manual positioning (more reliable than dagre)
    const layoutedNodes = newNodes.map((node, index) => {
      if (node.id === 'c2-server') {
        // C2 server on the left, centered
        return {
          ...node,
          position: { x: 50, y: 250 },
          targetPosition: Position.Left,
          sourcePosition: Position.Right,
        };
      } else {
        // Agents distributed vertically on the right, centered around C2
        const agentIndex = index - 1; // Subtract 1 for C2 server
        const totalAgents = newNodes.length - 1; // Exclude C2
        const startY = 250 - ((totalAgents - 1) * 150); // Center around C2 with more spacing
        return {
          ...node,
          position: { x: 450, y: startY + (agentIndex * 300) },
          targetPosition: Position.Left,
          sourcePosition: Position.Right,
        };
      }
    });
    
    setNodes(layoutedNodes);
    setEdges(newEdges);
  }, [nimplants]);

    return (
    <div style={{ 
      width: '100%', 
      height: 'calc(100vh - 300px)',
      minHeight: '500px',
      background: '#0B1622',  // Nimhawk official background
      border: '1px solid #00FF88',
      borderRadius: '12px',
    }}>
      <ReactFlow
        nodes={nodes}
        edges={edges}
        onNodesChange={onNodesChange}
        onEdgesChange={onEdgesChange}
        onConnect={onConnect}
        nodeTypes={nodeTypes}
        nodesDraggable
        nodesConnectable={false}
        minZoom={0.3}
        maxZoom={1.5}
        defaultViewport={{ x: 0, y: 0, zoom: 0.8 }}
        proOptions={{ hideAttribution: true }}
      />
    </div>
  );
}

export default function TopologyPage() {
  const [topologies, setTopologies] = useState<TopologyData[]>([]);
  const [nimplants, setNimplants] = useState<NimplantData[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const fetchData = async () => {
    try {
      setError(null);
      
      // Fetch nimplants first, then topology if needed
      const nimplantsData = await api.get('/api/nimplants');
      
      // Map the API fields to our expected interface
      const mappedNimplants = Array.isArray(nimplantsData) ? nimplantsData.map((nimplant: any) => ({
        guid: nimplant.guid,
        hostname: nimplant.hostname,
        username: nimplant.username,
        ip_external: nimplant.ipAddrExt,
        ip_internal: nimplant.ipAddrInt,
        os_build: nimplant.os_build || 'Unknown',
        process_name: nimplant.pname,
        relay_role: nimplant.relay_role || 'STANDARD',
        active: nimplant.active,
        late: nimplant.late
      })) : [];
      
      setNimplants(mappedNimplants);
      
      // Try to fetch topology data, but don't fail if it doesn't exist
      try {
        const topologyData = await api.get('/api/topology');
        setTopologies(topologyData.topologies || []);
      } catch (topologyErr) {
        console.warn('Topology data not available:', topologyErr);
        setTopologies([]);
      }
      
    } catch (err) {
      console.error('Error fetching data:', err);
      setError('Failed to fetch network data');
      setTopologies([]);
      setNimplants([]);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchData();
    
    // Auto-refresh every 30 seconds
    const interval = setInterval(fetchData, 30000);
    return () => clearInterval(interval);
  }, []);

  const handleRefresh = () => {
    setLoading(true);
    fetchData();
  };



  return (
    <AuthWrapper>
      <div style={{ 
        position: 'fixed',
        top: '0',
        left: '80px',
        right: '0',
        bottom: '0',
        paddingTop: '80px',
        paddingBottom: '16px',
        paddingLeft: '16px',
        paddingRight: '16px',
        overflowY: 'auto',
        backgroundColor: '#f8f9fa'
      }}>
          <div style={{ marginBottom: '24px', marginTop: '8px' }}>
            <Title order={2} mb="xs">
              <FaNetworkWired style={{ marginRight: '8px' }} />
              Network Topology
            </Title>
            <Text c="dimmed">
              Hierarchical view of network connections
            </Text>
          </div>



          {error && (
            <Alert 
              icon={<FaExclamationTriangle />} 
              title="Error" 
              color="red" 
              mb="md"
            >
              {error}
            </Alert>
          )}

          {/* Topology Graph */}
          <Card withBorder p="md" radius="md" style={{ 
            position: 'relative',
            background: '#1a1a1a',
            border: '1px solid #333'
          }}>
            <LoadingOverlay visible={loading} />
            
            <Group justify="space-between" mb="md">
              <Title order={3} style={{ color: '#ffffff' }}>
                Implants connections flow
              </Title>
              <Button 
                leftSection={<FaSyncAlt />} 
                onClick={handleRefresh} 
                loading={loading}
                variant="light"
                size="sm"
              >
                Refresh
              </Button>
            </Group>
            
            <TopologyGraph topologies={topologies} nimplants={nimplants} />
            
            {!loading && nimplants.length === 0 && (
              <Stack align="center" py="xl">
                <FaNetworkWired size={48} color="#64748b" />
                <Text size="lg" ta="center" style={{ color: '#cbd5e1' }}>
                  No agents connected
                </Text>
                <Text size="sm" ta="center" style={{ color: '#94a3b8' }}>
                  Agents will appear here when they connect to the C2
                </Text>
              </Stack>
            )}
          </Card>


        </div>
    </AuthWrapper>
  );
} 