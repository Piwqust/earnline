// A plain white surface. Used for rail panels, settings groups, detail sections.
// Kept deliberately thin — no nested cards.
import type { ReactNode } from "react";

export function Card({
  className,
  children,
}: {
  className?: string;
  children: ReactNode;
}) {
  return <section className={"card" + (className ? " " + className : "")}>{children}</section>;
}
