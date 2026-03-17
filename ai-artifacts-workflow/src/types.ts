export type NodeCategory = 'input' | 'ai' | 'transform' | 'output';

export interface NodeTemplate {
  type: string;
  label: string;
  category: NodeCategory;
  description: string;
  color: string;
  inputs: string[];
  outputs: string[];
  fields: FieldDef[];
}

export interface FieldDef {
  name: string;
  label: string;
  type: 'text' | 'textarea' | 'select' | 'number';
  options?: string[];
  defaultValue?: string;
}
