import { useCallback, useRef } from 'react';
import {
  ReactFlow,
  Controls,
  Background,
  BackgroundVariant,
  MiniMap,
  addEdge,
  useNodesState,
  useEdgesState,
  type OnConnect,
  type Node,
  type Edge,
  ReactFlowProvider,
} from '@xyflow/react';
import '@xyflow/react/dist/style.css';

import WorkflowNode from './nodes/WorkflowNode';
import type { WorkflowNodeData } from './nodes/WorkflowNode';
import Sidebar from './components/Sidebar';
import Toolbar from './components/Toolbar';
import { nodeTemplates } from './nodeTemplates';
import './App.css';

const nodeTypes = { workflowNode: WorkflowNode };

const initialNodes: Node[] = [];
const initialEdges: Edge[] = [];

let nodeId = 0;
const getNextId = () => `node_${++nodeId}`;

function Flow() {
  const reactFlowWrapper = useRef<HTMLDivElement>(null);
  const [nodes, setNodes, onNodesChange] = useNodesState(initialNodes);
  const [edges, setEdges, onEdgesChange] = useEdgesState(initialEdges);

  const onConnect: OnConnect = useCallback(
    (params) => setEdges((eds) => addEdge({ ...params, animated: true }, eds)),
    [setEdges]
  );

  const onDragOver = useCallback((event: React.DragEvent) => {
    event.preventDefault();
    event.dataTransfer.dropEffect = 'move';
  }, []);

  const onDrop = useCallback(
    (event: React.DragEvent) => {
      event.preventDefault();

      const templateType = event.dataTransfer.getData('application/reactflow');
      if (!templateType) return;

      const template = nodeTemplates.find((t) => t.type === templateType);
      if (!template) return;

      const bounds = reactFlowWrapper.current?.getBoundingClientRect();
      if (!bounds) return;

      const position = {
        x: event.clientX - bounds.left - 100,
        y: event.clientY - bounds.top - 20,
      };

      const fieldValues: Record<string, string> = {};
      template.fields.forEach((f) => {
        fieldValues[f.name] = f.defaultValue ?? '';
      });

      const newNode: Node = {
        id: getNextId(),
        type: 'workflowNode',
        position,
        data: {
          templateType: template.type,
          fieldValues,
          label: template.label,
        } satisfies WorkflowNodeData,
      };

      setNodes((nds) => [...nds, newNode]);
    },
    [setNodes]
  );

  const onClear = useCallback(() => {
    setNodes([]);
    setEdges([]);
  }, [setNodes, setEdges]);

  return (
    <div className="app">
      <Sidebar />
      <div className="canvas-wrapper" ref={reactFlowWrapper}>
        <Toolbar onClear={onClear} />
        <ReactFlow
          nodes={nodes}
          edges={edges}
          onNodesChange={onNodesChange}
          onEdgesChange={onEdgesChange}
          onConnect={onConnect}
          onDragOver={onDragOver}
          onDrop={onDrop}
          nodeTypes={nodeTypes}
          fitView
          deleteKeyCode={['Backspace', 'Delete']}
          proOptions={{ hideAttribution: true }}
        >
          <Controls />
          <MiniMap
            nodeStrokeWidth={3}
            pannable
            zoomable
            style={{ background: '#1a1a2e' }}
          />
          <Background
            variant={BackgroundVariant.Dots}
            gap={20}
            size={1}
            color="#333"
          />
        </ReactFlow>
      </div>
    </div>
  );
}

export default function App() {
  return (
    <ReactFlowProvider>
      <Flow />
    </ReactFlowProvider>
  );
}
