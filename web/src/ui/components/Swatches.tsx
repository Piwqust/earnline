// Color picker — a row of brand-palette circles.
export function Swatches({
  colors,
  value,
  onChange,
}: {
  colors: string[];
  value: string;
  onChange: (hex: string) => void;
}) {
  return (
    <div className="swatches" role="radiogroup" aria-label="Color">
      {colors.map((hex) => {
        const selected = hex === value;
        return (
          <button
            key={hex}
            type="button"
            role="radio"
            aria-checked={selected}
            aria-label={`Color ${hex}`}
            className={"swatch" + (selected ? " is-selected" : "")}
            style={{ background: hex, color: hex }}
            onClick={() => onChange(hex)}
          />
        );
      })}
    </div>
  );
}
