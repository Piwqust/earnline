// Create or rename a month heading. Replaces the HeadingEditor sheet.
import { useId, useState } from "react";
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
  const [isSaving, setIsSaving] = useState(false);
  const [saveError, setSaveError] = useState<string | null>(null);
  const titleId = useId();
  const clean = trimmed(title, Limits.maxHeadingLength);

  async function save() {
    if (clean === "") return;
    setIsSaving(true);
    setSaveError(null);
    try {
      if (heading) await updateHeading(heading.id, { title: clean });
      else await createHeading({ title: clean, date: monthMs, sortIndex: nextSortIndex });
      queueSync();
      onClose();
    } catch {
      setSaveError("The heading could not be saved. Try again.");
    } finally {
      setIsSaving(false);
    }
  }

  return (
    <Dialog
      title={heading ? "Rename heading" : "New heading"}
      size="sm"
      onClose={onClose}
      footer={
        <>
          <button type="button" className="btn btn--secondary btn--md" disabled={isSaving} onClick={onClose}>
            <span>Cancel</span>
          </button>
          <button
            type="button"
            className="btn btn--primary btn--md"
            disabled={clean === "" || isSaving}
            onClick={() => void save()}
          >
            <span>{isSaving ? "Saving…" : heading ? "Save" : "Add heading"}</span>
          </button>
        </>
      }
    >
      <Field label="Title" htmlFor={titleId}>
        <input
          id={titleId}
          className="input"
          data-autofocus
          placeholder="e.g. Retainers"
          value={title}
          required
          onChange={(e) => {
            setTitle(e.target.value.slice(0, Limits.maxHeadingLength));
            setSaveError(null);
          }}
          onKeyDown={(e) => {
            if (e.key === "Enter" && clean !== "") void save();
          }}
        />
        {saveError && (
          <p className="field__error" role="alert">
            {saveError}
          </p>
        )}
      </Field>
    </Dialog>
  );
}
