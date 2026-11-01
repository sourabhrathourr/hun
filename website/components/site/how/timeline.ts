// One run of the section, as a function of time: the terminal types
// `hun run orbit`, orbit starts (the ticket is punched, the menu bar switch
// turns on), then `hun status` prints. Pausing, the settled ?shot and
// reduced motion are all just a value of t.

export const CMD_RUN = "hun run orbit";
export const CMD_STATUS = "hun status";

/** A typist's rhythm: uneven, but the same on every visit. */
const KEY_GAPS = [96, 64, 78, 120, 58, 70, 88, 132, 62, 74, 66, 92];
const keyAt = (start: number, n: number) => {
  let t = start;
  for (let i = 0; i < n; i++) t += KEY_GAPS[i % KEY_GAPS.length];
  return t;
};

export const TYPE_1 = 650;
export const ENTER_1 = keyAt(TYPE_1, CMD_RUN.length) + 280;
/** Hun starts postgres and app first, then server and worker. */
export const STARTED = ENTER_1 + 1100;
export const TYPE_2 = STARTED + 750;
export const ENTER_2 = keyAt(TYPE_2, CMD_STATUS.length) + 260;
export const STATUS = ENTER_2 + 140;
export const END = STATUS;

export type Menu = "idle" | "starting" | "running";

export interface Frame {
  /** Characters of each command typed so far. */
  typed1: number;
  typed2: number;
  ran1: boolean;
  started: boolean;
  ran2: boolean;
  status: boolean;
  /** The caret blinks when the shell is waiting, and holds still while keys land. */
  idle: boolean;
  menu: Menu;
}

function typed(t: number, start: number, len: number) {
  if (t < start) return 0;
  let at = start;
  for (let i = 0; i < len; i++) {
    at += KEY_GAPS[i % KEY_GAPS.length];
    if (t < at) return i;
  }
  return len;
}

export function frameAt(t: number): Frame {
  const typed1 = typed(t, TYPE_1, CMD_RUN.length);
  const typed2 = typed(t, TYPE_2, CMD_STATUS.length);
  const ran1 = t >= ENTER_1;
  const started = t >= STARTED;
  const ran2 = t >= ENTER_2;
  const status = t >= STATUS;
  // Typing, or waiting on a command: the caret holds still.
  const busy = (t >= TYPE_1 - 120 && t < STARTED) || (t >= TYPE_2 - 120 && t < STATUS);
  return {
    typed1,
    typed2,
    ran1,
    started,
    ran2,
    status,
    idle: !busy,
    menu: started ? "running" : t >= ENTER_1 + 180 ? "starting" : "idle",
  };
}
