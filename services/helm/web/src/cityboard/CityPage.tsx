// The city's page, beside the rig pages, at the address ?city: what doctor
// found in its newest recorded run, and how many messages wait in the
// operator's mailbox. The page reads one document (GET <mount>/helm/city),
// which decides which checks show, which count in the lead, their order, and
// whether the run is late, and lays it out in rows drawn with the board's one
// row structure (Line). Each check is drawn the same way in whichever list
// holds it. The page derives no state of its own.

import { useEffect, useState, type ReactNode } from 'react';
import { Line } from '../rigboard/Line';
import { readCity } from '../rigboard/read';
import { Note } from '../rigboard/rows';
import { usePolledRead, type ReadState } from '../rigboard/usePolledRead';
import { AMBER, INK, MUTE } from '../rigboard/view';
import type { Check, Doctor, Mail, Monitor, Response as CityResponse } from './document.gen';

// The service serves doctor's part of the city's document from its cache for
// five minutes (server.CityPageTTL), so reading more often than every two and
// a half minutes re-reads the same run. The mailbox's count it serves from its
// cache for a minute (server.CityMailTTL), so the count on screen is at most
// three and a half minutes old.
export const CITY_REFRESH_MS = 150_000;

const WHITE = '#FFFFFF';
const RULE = '#E6E7E2';
const RED = '#B3261E';
const GREEN = '#1E7A4C';

export function CityPage() {
  const [state] = usePolledRead(readCity, CITY_REFRESH_MS);
  useEffect(() => {
    document.title = 'helm · city';
  }, []);
  const doctor = state.last?.city.doctor;
  const mail = state.last?.city.mail;
  return (
    <div className="page">
      <header className="bar">
        <span className="brand">helm</span>
        <nav aria-label="City and rigs" className="rig-nav">
          <span className="rig-current">City</span>
          <a href="./" title="All of the city's rigs">
            Rigs
          </a>
        </nav>
      </header>
      <div className="body">
        <main className="main">
          <ReadStatus state={state} />
          {doctor !== undefined && <DoctorView doctor={doctor} mail={mail} />}
        </main>
      </div>
    </div>
  );
}

/** A time the document gives, to the minute, in the reader's own zone. */
export function when(at: string): string {
  const d = new Date(at);
  return Number.isNaN(d.getTime())
    ? at
    : d.toLocaleString(undefined, { month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit' });
}

/** When the page on screen was read, and the latest read's failure beside it.
 *  A failed read never draws an empty page: with no document read yet, the
 *  page shows the failure alone. */
function ReadStatus({ state }: { state: ReadState<CityResponse> }) {
  const last = state.last;
  if (last === undefined) {
    if (state.failure !== undefined) {
      return (
        <p className="status status--failed" role="alert">
          The city page could not be read: {state.failure.message}
        </p>
      );
    }
    return <Note>Reading the city page…</Note>;
  }
  if (state.failure !== undefined) {
    return (
      <p className="status status--failed" role="alert">
        The latest read failed at {state.failure.at.toLocaleTimeString()}: {state.failure.message}. This is the page
        read at {when(last.read_at)}.
      </p>
    );
  }
  return <p className="status">Read at {when(last.read_at)}.</p>;
}

type Part = 'failing' | 'not_measured' | 'accepted' | 'monitors';

/** Whether each part is open before the operator folds it: the accepted checks
 *  are folded under their count. */
const OPEN: Record<Part, boolean> = { failing: true, not_measured: true, accepted: false, monitors: true };

function DoctorView({ doctor: d, mail }: { doctor: Doctor; mail: Mail | undefined }) {
  const [open, setOpen] = useState<Record<Part, boolean>>(OPEN);
  if (!d.ran) {
    return (
      <>
        <Note>Doctor has recorded no run in the city's event log, so nothing here says which checks fail.</Note>
        <MailLead mail={mail} />
      </>
    );
  }
  const flip = (part: Part) => setOpen((prev) => ({ ...prev, [part]: !prev[part] }));
  const section = (part: Part, label: string, count: number, rows: ReactNode) => (
    <>
      <Line
        depth={0}
        look="section"
        gap={16}
        hasKids
        open={open[part]}
        onToggle={() => flip(part)}
        title={label}
        count={count}
        titleInk={INK}
      />
      {open[part] && rows}
    </>
  );
  return (
    <>
      {d.measured !== undefined && d.measured !== '' ? (
        <div className="lead">
          <span className="lead-count" style={{ color: d.count > 0 ? AMBER : GREEN }}>
            {d.count}
          </span>
          <span className="lead-text">{leadText(d)}</span>
        </div>
      ) : (
        <Note>No doctor run has measured the checks yet, so nothing here says which checks fail.</Note>
      )}
      <MailLead mail={mail} />
      <RunNote doctor={d} />
      {d.failing.length > 0 &&
        section(
          'failing',
          'Failing',
          d.failing.length,
          d.failing.map((c) => <CheckRow key={c.name} check={c} />),
        )}
      {d.not_measured.length > 0 &&
        section(
          'not_measured',
          'Not measured',
          d.not_measured.length,
          d.not_measured.map((c) => <CheckRow key={c.name} check={c} />),
        )}
      {d.accepted.length > 0 &&
        section(
          'accepted',
          'Accepted',
          d.accepted.length,
          d.accepted.map((c) => <CheckRow key={c.name} check={c} />),
        )}
      {section(
        'monitors',
        'Monitor orders',
        d.monitors.length,
        <>
          {d.monitors_unread !== undefined && d.monitors_unread !== '' && (
            <Note>
              The last run could not read the monitor orders' runs ({d.monitors_unread}), so these are what the run
              before it recorded.
            </Note>
          )}
          {d.monitors.map((m) => (
            <MonitorRow key={m.order} monitor={m} />
          ))}
        </>,
      )}
    </>
  );
}

/** The words after the lead's count. The count is of the checks two runs in a
 *  row found failing, so at every count the words say so, and name the accepted
 *  checks and the checks not measured, which it leaves out. */
function leadText(d: Doctor): string {
  const failed = d.count === 0 ? 'No check has' : d.count === 1 ? 'check has' : 'checks have';
  const left = [
    d.accepted.length > 0 ? `${d.accepted.length} accepted` : '',
    d.not_measured.length > 0 ? `${d.not_measured.length} not measured` : '',
  ].filter((s) => s !== '');
  return `${failed} failed two runs in a row${left.length > 0 ? `, not counting ${left.join(' and ')}` : ''}.`;
}

/** How many messages wait in the operator's mailbox, read or not, beside the
 *  failing checks, with how to open the mayor, who works through it with
 *  them. A count that did not read shows why in place of a number, and a
 *  document with no count shows nothing. */
function MailLead({ mail }: { mail: Mail | undefined }) {
  if (mail === undefined || !mail.counted) {
    return mail?.why !== undefined && mail.why !== '' ? <Note>Your mailbox could not be counted: {mail.why}.</Note> : null;
  }
  const n = mail.waiting;
  return (
    <div className="lead">
      <span className="lead-count" style={{ color: n > 0 ? AMBER : GREEN }}>
        {n}
      </span>
      <span className="lead-text">
        {n === 1 ? 'message waits' : 'messages wait'} in your mailbox, read or not.
        {n > 0 && ` Open the mayor to work through ${n === 1 ? 'it' : 'them'}: gc-helm mayor.`}
        {mail.short !== undefined && mail.short !== '' && ` The count may miss some: ${mail.short}.`}
      </span>
    </div>
  );
}

/** When doctor last ran, whether that is late, and whether the run completed. */
function RunNote({ doctor: d }: { doctor: Doctor }) {
  return (
    <div className="note-line">
      <p>
        Doctor last ran at {when(d.started ?? '')}.
        {d.late && (
          <strong style={{ color: AMBER }}> Late: doctor runs every hour, and this run started over two hours ago.</strong>
        )}
        {!d.completed && (
          <>
            {' '}
            That run did not complete: {d.why}.
            {d.measured !== undefined && d.measured !== '' && <> The checks below are what the run at {when(d.measured)} measured.</>}
          </>
        )}
      </p>
    </div>
  );
}

/** Why a run did not measure a check, in words. */
function unmeasuredWords(why: string): string {
  return why === 'timed_out' ? 'Not measured: doctor abandoned the check at its per-check timeout.' : `Not measured: ${why}`;
}

/** One check, drawn the same way in whichever list holds it. */
function CheckRow({ check: c }: { check: Check }) {
  const unmeasured = c.unmeasured !== undefined && c.unmeasured !== '';
  const tag = unmeasured
    ? { text: 'not measured', ink: MUTE }
    : c.status !== undefined && c.status !== ''
      ? { text: c.status, ink: c.status === 'error' ? RED : AMBER }
      : undefined;
  const failing = c.first_failed !== undefined && c.first_failed !== '';
  const runs = c.streak ?? 0;
  const bits: ReactNode[] = [];
  if (c.severity !== undefined && c.severity !== '') {
    bits.push(
      <span key="severity" className="bit">
        {c.severity}
      </span>,
    );
  }
  if (c.accepted !== undefined) {
    bits.push(
      <span key="accepted" className="bit bit--ref">
        Accepted{c.accepted.for !== undefined && c.accepted.for !== '' ? ` for ${c.accepted.for} from its first failure` : ''}:{' '}
        {c.accepted.reason} Ruling: {c.accepted.ruling}
      </span>,
    );
  }
  return (
    <Line
      depth={1}
      look="item"
      bg={WHITE}
      rule={RULE}
      hasKids={false}
      open={false}
      onToggle={() => {}}
      tag={tag}
      title={c.name}
      titleInk={INK}
      signal={
        failing
          ? {
              text: `failing since ${when(c.first_failed ?? '')}`,
              note: `${runs} ${runs === 1 ? 'run' : 'runs in a row'}`,
              ink: c.accepted !== undefined ? MUTE : AMBER,
            }
          : undefined
      }
      line2={unmeasured ? unmeasuredWords(c.unmeasured ?? '') : c.message}
      bits={bits}
    />
  );
}

/** A monitor order and its last good run. Whether it is late is Gas City's
 *  verdict, in its order checks, which the page lists as checks. */
function MonitorRow({ monitor: m }: { monitor: Monitor }) {
  const good = m.last_good !== undefined && m.last_good !== '';
  return (
    <Line
      depth={1}
      look="item"
      bg={WHITE}
      rule={RULE}
      hasKids={false}
      open={false}
      onToggle={() => {}}
      title={m.order}
      titleInk={INK}
      signal={{ text: good ? `last good run ${when(m.last_good ?? '')}` : 'no good run known', ink: MUTE }}
    />
  );
}
