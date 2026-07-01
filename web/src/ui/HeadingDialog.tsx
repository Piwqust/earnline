// Create or rename a month heading. Replaces the HeadingEditor sheet.
import { useState } from "react";
import type { Heading } from "../domain/types";
import { Limits, trimmed } from "../domain/validation";
import { createHeading, updateHeading } from "../data/repository";
import { queueSync } from "../state/store";
import { Dialog } from "./components/Dialog";
import { Field } from "./components/Field";

export function HeadingDialog({
  heading,
  monthMs,
  nextSortIndex,
  onClose,
}: {
  heading: Heading | null;
  monthMs: number;
  nextSortIndex: number;
  onClose: () => void;
}) {
  const [title, setTitle] = useState(heading?.title ?? "");
  const clean = trimmed(title, Limits.maxHeadingLength);

  async function save() {
    if (clean === "") return;
    if (heading) await updateHeading(heading.id, { title: clean });
    else await createHeading({ title: clean, date: monthMs, sortIndex: nextSortIndex });
    queueSync();
    onClose();
  }

  return (
    <Dialog
      title={heading ? "Rename heading" : "New heading"}
      size="sm"
      onClose={onClose}
      footer={
        <>
          <button type="button" className="btn btn--secondary btn--md" onClick={onClose}>
            <span>Cancel</span>
          </button>
          <button
            type="button"
            className="btn btn--primary btn--md"
            disabled={clean === ""}
            onClick={() => void save()}
          >
            <span>{heading ? "Save" : "Add heading"}</span>
          </button>
        </>
      }
    >
      <Field label="Title">
        <input
          className="input"
          data-autofocus
          placeholder="e.g. Retainers"
          value={title}
          onChange={(e) => setTitle(e.target.value.slice(0, Limits.maxHeadingLength))}
          onKeyDown={(e) => {
            if (e.key === "Enter" && clean !== "") void save();
          }}
        />
      </Field>
    </Dialog>
  );
}
