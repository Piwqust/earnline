// One income line, desktop-tabular. Click the row to edit; the status dot opens
// a quick status menu; a delete action surfaces on hover.
import type { Entry, EntryStatus } from "../domain/types";
import { STATUS_ORDER, statusTitle } from "../domain/types";
import { canConvert, toBase } from "../domain/currency";
import { numberFromCents } from "../domain/money";
import { dottedDay } from "../domain/dateFormat";
import { useSettings, currencySettings } from "../state/settings";
import { MoneyAmountText } from "./MoneyAmountText";
import { Dropdown, DropdownItem, DropdownDivider } from "./components/Dropdown";
import { CalendarIcon, MoreIcon, PencilIcon, StatusIcon, TrashIcon } from "./icons";

export function EntryRow({
  entry,
  onSetStatus,
  onEdit,
  onDelete,
}: {
  entry: Entry;
  onSetStatus: (s: EntryStatus) => void;
  onEdit: () => void;
  onDelete: () => void;
}) {
  const settings = useSettings();
  const cs = currencySettings(settings);
  const base = toBase(numberFromCents(entry.amountCents), entry.currencyCode, cs);
  const approximate = !canConvert(entry.currencyCode, cs);

  return (
    <div
      className="entry"
      role="button"
      tabIndex={0}
      onClick={onEdit}
      onKeyDown={(e) => {
        if (e.key === "Enter") {
          e.preventDefault();
          onEdit();
        }
      }}
    >
      <MoneyAmountText baseAmount={base} approximate={approximate} className="entry__amount tabular" />

      <div className="entry__desc" title={entry.task}>
        {entry.project && <span className="entry__project">{entry.project}</span>}
        {entry.project && <span className="entry__colon"> : </span>}
        <span className="entry__task">{entry.task}</span>
      </div>

      <div className="entry__date">
        <span>{dottedDay(entry.date)}</span>
        {entry.holdUntil != null && (
          <span className="entry__hold">
            <CalendarIcon size={12} />
            <span>hold {dottedDay(entry.holdUntil)}</span>
          </span>
        )}
      </div>

      <span className="entry__status" onClick={(e) => e.stopPropagation()}>
        <Dropdown
          ariaLabel="Change status"
          triggerClassName="entry__statusbtn"
          trigger={<StatusIcon status={entry.status} size={18} />}
        >
          {STATUS_ORDER.map((s) => (
            <DropdownItem key={s} onClick={() => onSetStatus(s)}>
              <StatusIcon status={s} size={16} />
              <span>{statusTitle(s)}</span>
            </DropdownItem>
          ))}
        </Dropdown>
      </span>

      <span className="entry__more" onClick={(e) => e.stopPropagation()}>
        <Dropdown ariaLabel="Line actions" triggerClassName="entry__morebtn" trigger={<MoreIcon size={17} />}>
          <DropdownItem onClick={onEdit}>
            <PencilIcon size={15} />
            <span>Edit line</span>
          </DropdownItem>
          <DropdownDivider />
          <DropdownItem destructive onClick={onDelete}>
            <TrashIcon size={15} />
            <span>Delete line</span>
          </DropdownItem>
        </Dropdown>
      </span>
    </div>
  );
}
