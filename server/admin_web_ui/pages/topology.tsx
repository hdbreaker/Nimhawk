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
// dagre import removed - using custom positioning

import 'reactflow/dist/style.css';

import AuthWrapper from '../components/AuthWrapper';
import MainLayout from '../components/MainLayout';
import NimplantDrawer from '../components/NimplantDrawer';
import { api } from '../modules/apiFetcher';

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
  disconnected: boolean;
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

// Helper function to get OS icon image path
const getOSIcon = (os: string) => {
  console.log('[DEBUG TOPOLOGY] getOSIcon called with:', os, 'Type:', typeof os);
  
  if (!os || os === 'Unknown' || os === 'unknown') {
    console.log('[DEBUG TOPOLOGY] getOSIcon: OS is Unknown or empty, returning question mark');
    return null; // Will show text fallback
  }
  
  const osLower = os.toLowerCase();
  console.log('[DEBUG TOPOLOGY] getOSIcon: OS lowercase:', osLower);
  
  if (osLower.includes('windows') || osLower.includes('win') || osLower.includes('microsoft')) {
    console.log('[DEBUG TOPOLOGY] getOSIcon: Detected Windows');
    return '/windows.png';
  }
  
  if (osLower.includes('linux') || osLower.includes('ubuntu') || osLower.includes('debian') || osLower.includes('centos') || osLower.includes('redhat')) {
    console.log('[DEBUG TOPOLOGY] getOSIcon: Detected Linux');
    return '/linux.png';
  }
  
  if (osLower.includes('darwin') || osLower.includes('macos') || osLower.includes('mac') || osLower.includes('osx')) {
    console.log('[DEBUG TOPOLOGY] getOSIcon: Detected macOS/Darwin');
    return '/mac.png';
  }
  
  if (osLower.includes('android')) {
    console.log('[DEBUG TOPOLOGY] getOSIcon: Detected Android');
    return null; // Could add android.png later
  }
  
  if (osLower.includes('ios')) {
    console.log('[DEBUG TOPOLOGY] getOSIcon: Detected iOS');
    return null; // Could add ios.png later
  }
  
  console.log('[DEBUG TOPOLOGY] getOSIcon: No match found, returning null');
  return null; // Will show text fallback
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

// Helper function to get relay role colors (logical hierarchy)
const getRelayRoleColor = (relayRole: string) => {
  switch (relayRole) {
    case 'RELAY_SERVER': return '#F59E0B';   // Amber/Orange warning (important server role)
    case 'RELAY_HYBRID': return '#8B5CF6';   // Purple/Violet (hybrid role - most complex)
    case 'RELAY_CLIENT': return '#00FF88';   // Green (client role)
    case 'STANDARD': return '#9CA3AF';       // Gray (neutral)
    default: return '#9CA3AF';               // Gray (neutral)
  }
};

// Helper function to get relay role display names
const getRelayRoleDisplayName = (relayRole: string) => {
  switch (relayRole) {
    case 'RELAY_SERVER': return 'RELAY SERVER';
    case 'RELAY_CLIENT': return 'RELAY CLIENT';
    case 'RELAY_HYBRID': return 'RELAY HYBRID';
    case 'STANDARD': return 'STANDARD';
    default: return 'STANDARD';
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
    width: '320px',
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

// Legacy buildTreeStructure removed - using only distributed chain relationships

// Custom node component with proper handles
const CustomNode = ({ data, id }: { data: any, id: string }) => {
  const handleClick = () => {
    if (data.onNodeClick) {
      data.onNodeClick(id);
    }
  };

  return (
    <div 
      style={{
        ...data.style,
        cursor: id !== 'c2-server' ? 'pointer' : 'default'
      }}
      onClick={handleClick}
    >
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

// Auto-layout function removed - using custom positioning

// Build tree structure using distributed chain relationships + standard agents (NEW APPROACH)
const buildDistributedTopologyStructure = (chainRelationships: any[], standardAgents: NimplantData[]): TreeNode => {
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

  console.log('[DEBUG DISTRIBUTED] Building topology from chain relationships:', chainRelationships);
  console.log('[DEBUG DISTRIBUTED] Building topology from standard agents:', standardAgents);

  // Process standard agents (direct C2 connections) even if no chain relationships
  const chainGuids = new Set(chainRelationships?.map(rel => rel.nimplant_guid) || []);
  
  if (standardAgents && standardAgents.length > 0) {
    standardAgents.forEach(agent => {
      // Only add agents that are NOT in chain relationships (= direct C2 connections)
      if (!chainGuids.has(agent.guid)) {
        const status: 'online' | 'late' | 'disconnected' = agent.active ? 'online' :
                                                           agent.late ? 'late' : 'disconnected';
        
        const standardNode: TreeNode = {
          id: agent.guid,
          type: agent.relay_role || 'STANDARD',
          status: status,
          ip: agent.ip_internal || 'No IP',
          os: agent.os_build || 'Unknown',
          hostname: agent.hostname || `Agent-${agent.guid.substring(0, 8)}`,
          children: []
        };
        
        c2Root.children.push(standardNode);
        console.log('[DEBUG DISTRIBUTED] ✅ Added STANDARD agent to C2:', agent.guid, 'Role:', agent.relay_role);
      }
    });
  }

  if (!chainRelationships || chainRelationships.length === 0) {
    console.log('[DEBUG DISTRIBUTED] No chain relationships found, showing only standard agents');
    return c2Root;
  }

  // Create map of all nodes by GUID
  const nodeMap = new Map<string, TreeNode>();

  // Sort function: ONLINE first, then LATE, then DISCONNECTED
  const sortByStatus = (a: TreeNode, b: TreeNode) => {
    const statusOrder = { 'online': 0, 'late': 1, 'disconnected': 2 };
    return statusOrder[a.status] - statusOrder[b.status];
  };

  // Create tree nodes from chain relationships
  chainRelationships.forEach(rel => {
    if (!nodeMap.has(rel.nimplant_guid)) {
      const status: 'online' | 'late' | 'disconnected' = rel.status === 'online' ? 'online' :
                                                         rel.status === 'late' ? 'late' : 'disconnected';
      
      const treeNode: TreeNode = {
        id: rel.nimplant_guid,
        type: rel.role || 'STANDARD',
        status: status,
        ip: rel.internal_ip || 'No IP',
        os: rel.os_build || 'Unknown',
        hostname: rel.hostname || `Agent-${rel.nimplant_guid.substring(0, 8)}`,
        children: []
      };
      
      nodeMap.set(rel.nimplant_guid, treeNode);
      console.log('[DEBUG DISTRIBUTED] Created node:', rel.nimplant_guid, 'Role:', rel.role, 'Parent:', rel.parent_guid);
    }
  });

  // Build parent-child relationships
  chainRelationships.forEach(rel => {
    const childNode = nodeMap.get(rel.nimplant_guid);
    
    if (rel.parent_guid && rel.parent_guid !== '') {
      // Has parent - add to parent's children
      const parentNode = nodeMap.get(rel.parent_guid);
      if (parentNode && childNode) {
        parentNode.children.push(childNode);
        console.log('[DEBUG DISTRIBUTED] ✅ Connected:', rel.parent_guid, '→', rel.nimplant_guid);
      } else {
        console.log('[DEBUG DISTRIBUTED] ❌ Parent not found for connection:', rel.parent_guid, '->', rel.nimplant_guid);
      }
    } else {
      // No parent - connects directly to C2
      if (childNode) {
        c2Root.children.push(childNode);
        console.log('[DEBUG DISTRIBUTED] ✅ Connected to C2:', rel.nimplant_guid);
      }
    }
  });

  // Sort all children by status
  c2Root.children.sort(sortByStatus);
  nodeMap.forEach(node => {
    node.children.sort(sortByStatus);
  });

  console.log('[DEBUG DISTRIBUTED] Final topology - C2 children:', c2Root.children.length);
  
  return c2Root;
};

// REMOVED: Legacy topology functions - now using only chain relationships

function TopologyGraph({ nimplants, chainRelationships, onNodeClick }: { nimplants: NimplantData[], chainRelationships: any[], onNodeClick: (nodeId: string) => void }) {
  const [nodes, setNodes, onNodesChange] = useNodesState([]);
  const [edges, setEdges, onEdgesChange] = useEdgesState([]);

  const onConnect = useCallback(
    (params: Edge | Connection) => setEdges((eds) => addEdge(params, eds)),
    [setEdges]
  );

  useEffect(() => {
    // Always build tree structure using distributed chain relationships + standard agents
    console.log('[DEBUG TOPOLOGY] Building topology from chain relationships');
    console.log('[DEBUG TOPOLOGY] Chain relationships:', chainRelationships);
    console.log('[DEBUG TOPOLOGY] Nimplants (standard agents):', nimplants?.length || 0);
    
    const tree = buildDistributedTopologyStructure(chainRelationships, nimplants);
    
    const newNodes: Node[] = [];
    const newEdges: Edge[] = [];

    // Create nodes for the tree
    const createTreeNode = (treeNode: TreeNode): Node => {
      console.log('[DEBUG NODE] Creating node for:', treeNode.id, 'OS field:', treeNode.os);
      const statusColor = getStatusColor(treeNode.status);
      const osIconPath = getOSIcon(treeNode.os);
      console.log('[DEBUG NODE] OS icon path for', treeNode.id, ':', osIconPath);
      
      // Special styling for C2 server
      if (treeNode.id === 'c2-server') {
        return {
          id: treeNode.id,
          type: 'customNode',
          position: { x: 0, y: 0 }, // Will be set by dagre layout
          data: {
            style: createTreeNodeStyle(treeNode.status, true),
            onNodeClick: onNodeClick,
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
                  Team Server
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
          style: createTreeNodeStyle(treeNode.status, false),
          onNodeClick: onNodeClick,
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
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'center',
                  flexShrink: 0
                }}>
                  {osIconPath ? (
                    <img 
                      src={osIconPath} 
                      alt="OS"
                      style={{
                        width: '32px',
                        height: '32px',
                        filter: 'brightness(0.9)',
                        objectFit: 'contain'
                      }}
                    />
                  ) : (
                    <span style={{
                      fontSize: '18px',
                      fontWeight: 'bold',
                      color: '#AAAAAA',
                      border: '2px solid #AAAAAA',
                      borderRadius: '6px',
                      padding: '4px 6px',
                      display: 'inline-block',
                      minWidth: '28px',
                      textAlign: 'center'
                    }}>
                      {treeNode.os.includes('mac') || treeNode.os.includes('darwin') ? 'M' :
                       treeNode.os.includes('win') ? 'W' :
                       treeNode.os.includes('linux') ? 'L' : '?'}
                    </span>
                  )}
                </div>
                <div style={{ flex: 1, minWidth: 0 }}>
                  <div style={{ 
                    fontSize: '16px', 
                    fontWeight: 'bold',
                    color: '#ffffff',
                    marginBottom: '2px'
                  }}>
                    {treeNode.hostname.length > 28 
                      ? `${treeNode.hostname.substring(0, 24)}...` 
                      : treeNode.hostname}
                  </div>
                  <div style={{ 
                    fontSize: '12px', 
                    color: '#AAAAAA'
                  }}>
                    ID: {treeNode.id.substring(0, 8).toUpperCase()}
                  </div>
                </div>
              </div>
              
              {/* Relay Role Tag - Colorful and Prominent */}
              <div style={{ 
                display: 'flex',
                gap: '8px',
                marginBottom: '8px',
                alignItems: 'center'
              }}>
                <div style={{
                  display: 'inline-block',
                  background: 'transparent',
                  color: getRelayRoleColor(treeNode.type),
                  padding: '4px 8px',
                  borderRadius: '8px',
                  fontSize: '10px',
                  fontWeight: '700',
                  textTransform: 'uppercase' as const,
                  border: `1.5px solid ${getRelayRoleColor(treeNode.type)}`,
                }}>
                  {(() => {
                    console.log(`[DEBUG RENDER] Node ${treeNode.id} - Rendering type:`, treeNode.type);
                    return getRelayRoleDisplayName(treeNode.type);
                  })()}
                </div>
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
        const isOnline = child.status === 'online';
        newEdges.push({
          id: `${node.id}-to-${child.id}`,
          source: node.id,
          target: child.id,
          type: 'smoothstep',
          animated: false,
          style: { 
            stroke: childStatusColor,
            strokeWidth: 3,
            strokeDasharray: '8,4',
            ...(isOnline && {
              animation: 'dash 0.8s linear infinite',
              strokeDashoffset: '0',
            }),
          },
          // No arrow markers as requested
        });
        
        traverse(child);
      });
    };

    traverse(tree);
    
    // Apply hierarchical positioning that respects tree structure
    const positionedNodes: Node[] = [];
    const nodeDepth = new Map<string, number>(); // Track depth of each node
    const nodeLevelCounts = new Map<number, number>(); // Count nodes per level
    const nodeLevelIndices = new Map<number, number>(); // Track current index per level
    
    // First pass: calculate depths
    const calculateDepths = (node: TreeNode, depth: number) => {
      nodeDepth.set(node.id, depth);
      const currentCount = nodeLevelCounts.get(depth) || 0;
      nodeLevelCounts.set(depth, currentCount + 1);
      
      node.children.forEach(child => {
        calculateDepths(child, depth + 1);
      });
    };
    
    calculateDepths(tree, 0);
    
    // Initialize level indices
    Array.from(nodeLevelCounts.keys()).forEach(level => {
      nodeLevelIndices.set(level, 0);
    });
    
    // Second pass: position nodes based on depth and order
    const positionNode = (node: TreeNode) => {
      const depth = nodeDepth.get(node.id) || 0;
      const levelIndex = nodeLevelIndices.get(depth) || 0;
      const nodesInLevel = nodeLevelCounts.get(depth) || 1;
      
      // X position based on depth (each level 450px apart)
      const x = 50 + (depth * 450);
      
      // Y position: distribute nodes in this level vertically
      const levelHeight = nodesInLevel * 250; // 250px spacing between nodes
      const startY = 300 - (levelHeight / 2); // Center the level vertically
      const y = startY + (levelIndex * 250);
      
      // Find the ReactFlow node that corresponds to this tree node
      const reactFlowNode = newNodes.find(n => n.id === node.id);
      if (reactFlowNode) {
        positionedNodes.push({
          ...reactFlowNode,
          position: { x, y },
          targetPosition: Position.Left,
          sourcePosition: Position.Right,
        });
      }
      
      // Increment the level index for next node in this level
      nodeLevelIndices.set(depth, levelIndex + 1);
      
      // Position children
      node.children.forEach(child => {
        positionNode(child);
      });
    };
    
    positionNode(tree);
    
    const layoutedNodes = positionedNodes;
    
    setNodes(layoutedNodes);
    setEdges(newEdges);
  }, [chainRelationships, onNodeClick]);

    return (
    <div style={{ 
      width: '100%', 
      height: 'calc(100vh - 300px)',
      minHeight: '500px',
      background: '#0B1622',  // Nimhawk official background
      border: '1px solid rgb(114, 114, 115)',
      borderRadius: '12px',
    }}>
      <style jsx>{`
        @keyframes dash {
          to {
            stroke-dashoffset: -12;
          }
        }
      `}</style>
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
        defaultViewport={{ x: 0, y: 35, zoom: 0.75 }}
        proOptions={{ hideAttribution: true }}
      />
    </div>
  );
}

export default function TopologyPage() {
  const [nimplants, setNimplants] = useState<NimplantData[]>([]);
  const [chainRelationships, setChainRelationships] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  
  // Drawer state management
  const [drawerOpened, setDrawerOpened] = useState(false);
  const [selectedGuid, setSelectedGuid] = useState<string>('');

  // Handler for node clicks
  const handleNodeClick = useCallback((nodeId: string) => {
    // Don't open drawer for C2 server node
    if (nodeId === 'c2-server') {
      return;
    }
    
    console.log('Node clicked:', nodeId);
    setSelectedGuid(nodeId);
    setDrawerOpened(true);
  }, []);

  // Handler to close drawer
  const handleCloseDrawer = useCallback(() => {
    setDrawerOpened(false);
    setSelectedGuid('');
  }, []);

  // Handler for when implant is killed
  const handleImplantKilled = useCallback(() => {
    setDrawerOpened(false);
    setSelectedGuid('');
    // Refresh data to update the topology
    fetchData();
  }, []);

  const fetchData = async () => {
    try {
      setError(null);
      
      // Fetch nimplants first, then topology if needed
      console.log('[DEBUG TOPOLOGY] Fetching nimplants data...');
      const nimplantsData = await api.get('/api/nimplants');
      console.log('[DEBUG TOPOLOGY] Raw nimplants data received:', nimplantsData);
      
      // Map the API fields to our expected interface
      const mappedNimplants = Array.isArray(nimplantsData) ? nimplantsData.map((nimplant: any, index: number) => {
        console.log(`[DEBUG TOPOLOGY] Processing nimplant ${index}:`, nimplant);
        console.log(`[DEBUG TOPOLOGY] osBuild field for ${nimplant.guid}:`, nimplant.osBuild, 'Type:', typeof nimplant.osBuild);
        console.log(`[DEBUG TOPOLOGY] relay_role field for ${nimplant.guid}:`, nimplant.relay_role, 'Type:', typeof nimplant.relay_role);
        
        const mapped = {
          guid: nimplant.guid,
          hostname: nimplant.hostname,
          username: nimplant.username,
          ip_external: nimplant.ipAddrExt,
          ip_internal: nimplant.ipAddrInt,
          os_build: nimplant.osBuild || 'Unknown',
          process_name: nimplant.pname,
          relay_role: nimplant.relay_role || 'STANDARD',
          active: nimplant.active,
          late: nimplant.late,
          disconnected: nimplant.disconnected
        };
        
        console.log(`[DEBUG TOPOLOGY] Mapped nimplant ${index} - relay_role:`, mapped.relay_role);
        return mapped;
      }) : [];
      
      console.log('[DEBUG TOPOLOGY] Final mapped nimplants:', mappedNimplants);
      setNimplants(mappedNimplants);
      
      // Try to fetch chain relationships (NEW distributed approach)
      try {
        console.log('[DEBUG TOPOLOGY] Fetching chain relationships...');
        const chainData = await api.get('/api/chain-relationships');
        console.log('[DEBUG TOPOLOGY] Chain relationships received:', chainData);
        setChainRelationships(chainData.chain_relationships || []);
      } catch (chainErr) {
        console.warn('Chain relationships not available:', chainErr);
        setChainRelationships([]);
      }
      
      // REMOVED: Legacy topology fetching - now using only chain relationships
      
    } catch (err) {
      console.error('Error fetching data:', err);
      setError('Failed to fetch network data');
      setNimplants([]);
      setChainRelationships([]);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchData();
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
                Implants connection flow
              </Title>
              <Button 
                leftSection={<FaSyncAlt />} 
                onClick={handleRefresh} 
                loading={loading}
                variant="filled"
                color="gray"
                size="sm"
                style={{ 
                  backgroundColor: '#ffffff',
                  color: '#000000',
                  border: '1px solid #cccccc'
                }}
              >
                Refresh
              </Button>
            </Group>
            
            <TopologyGraph 
              nimplants={nimplants} 
              chainRelationships={chainRelationships}
              onNodeClick={handleNodeClick}
            />
            
            {!loading && chainRelationships.length === 0 && (
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

          <NimplantDrawer 
            opened={drawerOpened}
            onClose={handleCloseDrawer}
            guid={selectedGuid}
            onKilled={handleImplantKilled}
          />
        </div>
    </AuthWrapper>
  );
} 