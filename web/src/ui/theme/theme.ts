import type { EntryStatus } from "../../domain/types";

// Design tokens lifted from the earn›line Figma (Theme.swift).
export const BLUE = "#0088FF";
export const PURPLE = "#7B00FF";

export const STATUS_COLOR: Record<EntryStatus, string> = {
  paid: "#8E8E93", // gray — already paid, unremarkable
  inProgress: "#FF8A00", // orange — in progress
  canceled: "#FF3B30", // red — canceled
};

/** Calm palette offered when creating new clients. */
export const CLIENT_PALETTE: string[] = [
  "#0088FF", // blue
  "#7B00FF", // purple
  "#FF7A45", // coral
  "#16B364", // green
  "#E8467C", // pink
  "#0FB5BA", // teal
  "#F5A623", // amber
  "#6E56CF", // indigo
];

export function paletteColor(index: number): string {
  return CLIENT_PALETTE[index % CLIENT_PALETTE.length];
}
