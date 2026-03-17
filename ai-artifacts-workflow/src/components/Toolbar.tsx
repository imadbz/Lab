interface ToolbarProps {
  onClear: () => void;
}

export default function Toolbar({ onClear }: ToolbarProps) {
  return (
    <div className="toolbar">
      <button className="toolbar-btn" onClick={onClear} title="Clear canvas">
        Clear
      </button>
    </div>
  );
}
