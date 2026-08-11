// The "needs a human" strip: pending approvals, unread mail, parked work.
//
// Deliberately a sentence and not a badge cluster — the board's job is to be
// glanceable, and until the design loop chooses a visual language a plain line
// of text is the honest placeholder. It states zero as readily as it states a
// count, so a quiet city looks quiet rather than looking broken.

import { PartialNotice } from './PartialNotice';
import { useCitySignals } from './useCitySignals';

export function CitySignals() {
  const { pendingCount, unreadMail, waiting, partial, partialErrors, loading, error, unavailable } =
    useCitySignals();

  if (unavailable) return null;
  if (error !== null) {
    return (
      <p className="signals error" role="status">
        live signals unavailable: {error}
      </p>
    );
  }
  if (loading && !partial && pendingCount === 0 && unreadMail === 0 && waiting === 0) {
    return <p className="signals muted">reading city signals…</p>;
  }

  // A partial read makes every number a floor, so it is stated as one. "0
  // waiting on you" and "at least 0 waiting on you" are the same number and
  // very different claims — the first says go do something else.
  const count = (n: number) => (partial ? `at least ${n}` : String(n));

  return (
    <>
      <p className="signals" role="status">
        <strong>{count(pendingCount)}</strong> waiting on you
        {' · '}
        <strong>{count(unreadMail)}</strong> unread mail
        {' · '}
        <strong>{count(waiting)}</strong> parked on an answer
      </p>
      <PartialNotice partial={partial} what="these counts" reasons={partialErrors} />
    </>
  );
}
