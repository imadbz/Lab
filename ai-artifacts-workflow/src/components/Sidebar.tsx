import { nodeTemplates } from '../nodeTemplates';
import type { NodeCategory } from '../types';

const categories: { key: NodeCategory; label: string }[] = [
  { key: 'input', label: 'Inputs' },
  { key: 'ai', label: 'AI' },
  { key: 'transform', label: 'Transform' },
  { key: 'output', label: 'Outputs' },
];

export default function Sidebar() {
  const onDragStart = (event: React.DragEvent, templateType: string) => {
    event.dataTransfer.setData('application/reactflow', templateType);
    event.dataTransfer.effectAllowed = 'move';
  };

  return (
    <aside className="sidebar">
      <div className="sidebar-header">
        <h1>Artifact Studio</h1>
        <p className="sidebar-subtitle">Drag nodes onto the canvas</p>
      </div>
      {categories.map((cat) => (
        <div key={cat.key} className="sidebar-category">
          <h3 className="category-title">{cat.label}</h3>
          {nodeTemplates
            .filter((t) => t.category === cat.key)
            .map((template) => (
              <div
                key={template.type}
                className="sidebar-node"
                style={{ borderLeftColor: template.color }}
                draggable
                onDragStart={(e) => onDragStart(e, template.type)}
              >
                <span className="sidebar-node-label">{template.label}</span>
                <span className="sidebar-node-desc">{template.description}</span>
              </div>
            ))}
        </div>
      ))}
      <div className="sidebar-footer">
        <button className="run-button">
          <span className="run-icon">&#9654;</span> Run Workflow
        </button>
      </div>
    </aside>
  );
}
