import { memo, useCallback } from 'react';
import { Handle, Position, type NodeProps, useReactFlow } from '@xyflow/react';
import type { NodeTemplate, FieldDef } from '../types';
import { nodeTemplates } from '../nodeTemplates';

export type WorkflowNodeData = {
  templateType: string;
  fieldValues: Record<string, string>;
  label?: string;
};

function FieldInput({
  field,
  value,
  onChange,
}: {
  field: FieldDef;
  value: string;
  onChange: (name: string, value: string) => void;
}) {
  switch (field.type) {
    case 'textarea':
      return (
        <textarea
          className="node-field"
          rows={3}
          value={value}
          onChange={(e) => onChange(field.name, e.target.value)}
          placeholder={field.label}
        />
      );
    case 'select':
      return (
        <select
          className="node-field"
          value={value}
          onChange={(e) => onChange(field.name, e.target.value)}
        >
          {field.options?.map((opt) => (
            <option key={opt} value={opt}>
              {opt}
            </option>
          ))}
        </select>
      );
    case 'number':
      return (
        <input
          className="node-field"
          type="number"
          step="0.1"
          value={value}
          onChange={(e) => onChange(field.name, e.target.value)}
        />
      );
    default:
      return (
        <input
          className="node-field"
          type="text"
          value={value}
          onChange={(e) => onChange(field.name, e.target.value)}
          placeholder={field.label}
        />
      );
  }
}

function WorkflowNode({ id, data }: NodeProps) {
  const { updateNodeData } = useReactFlow();

  const nodeData = data as unknown as WorkflowNodeData;
  const template: NodeTemplate | undefined = nodeTemplates.find(
    (t) => t.type === nodeData.templateType
  );

  const onFieldChange = useCallback(
    (name: string, value: string) => {
      updateNodeData(id, {
        ...nodeData,
        fieldValues: { ...nodeData.fieldValues, [name]: value },
      });
    },
    [id, nodeData, updateNodeData]
  );

  if (!template) return <div>Unknown node</div>;

  return (
    <div className="workflow-node" style={{ borderTopColor: template.color }}>
      <div className="node-header" style={{ background: template.color }}>
        <span className="node-category">{template.category}</span>
        <span className="node-title">{template.label}</span>
      </div>
      <div className="node-body">
        {template.fields.map((field) => (
          <div key={field.name} className="node-field-group">
            <label className="node-field-label">{field.label}</label>
            <FieldInput
              field={field}
              value={nodeData.fieldValues[field.name] ?? field.defaultValue ?? ''}
              onChange={onFieldChange}
            />
          </div>
        ))}
        {template.category === 'output' && (
          <div className="node-preview-area">
            <span className="preview-placeholder">Output will appear here</span>
          </div>
        )}
      </div>

      {template.inputs.map((input, i) => (
        <Handle
          key={`in-${input}`}
          type="target"
          position={Position.Left}
          id={input}
          style={{ top: `${((i + 1) / (template.inputs.length + 1)) * 100}%` }}
          title={input}
        />
      ))}
      {template.outputs.map((output, i) => (
        <Handle
          key={`out-${output}`}
          type="source"
          position={Position.Right}
          id={output}
          style={{ top: `${((i + 1) / (template.outputs.length + 1)) * 100}%` }}
          title={output}
        />
      ))}
    </div>
  );
}

export default memo(WorkflowNode);
