// "This answer is not the whole answer" — rendered wherever the plane shows
// something a store did not fully report.
//
// The board reads across every rig in the city, and a rig store that does not
// answer is a normal Tuesday: the supervisor returns HTTP 200 with
// `partial: true` and a reason per store rather than failing the whole read.
// That is the right behaviour, and it puts the obligation here — an incomplete
// read that renders like a complete one is worse than an error, because the
// operator has no way to see that anything is missing. Same idea as the stock
// dashboard's PartialDataNotice.
//
// Structure only, like the rest of the app until U6.

export interface PartialNoticeProps {
  /** Whether the data behind this notice is known to be incomplete. */
  partial: boolean;
  /** What is incomplete, as a noun phrase: 'the session list', 'these counts'. */
  what: string;
  /**
   * Per-store reasons, when the supervisor gave any. `partial: true` with no
   * reasons is a real answer shape and still renders — the absence of a reason
   * is not evidence the data is fine.
   */
  reasons?: string[];
}

export function PartialNotice({ partial, what, reasons = [] }: PartialNoticeProps) {
  if (!partial) return null;
  return (
    <p className="partial" role="status">
      <strong>Incomplete:</strong> {what} came back partial — part of the city did not answer, so
      what you see here is a floor, not a total.
      {reasons.length > 0 && <span className="muted"> ({reasons.join('; ')})</span>}
    </p>
  );
}
