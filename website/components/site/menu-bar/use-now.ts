"use client";

import { useSyncExternalStore } from "react";

// One clock for every menu bar on the page, ticking on the minute.
let minute = 0;
const listeners = new Set<() => void>();
let timer: ReturnType<typeof setTimeout> | null = null;

function schedule() {
  const d = new Date();
  timer = setTimeout(() => {
    minute = Math.floor(Date.now() / 60_000);
    listeners.forEach((l) => l());
    schedule();
  }, 60_000 - (d.getSeconds() * 1000 + d.getMilliseconds()) + 50);
}

function subscribe(listener: () => void) {
  listeners.add(listener);
  if (!timer) {
    minute = Math.floor(Date.now() / 60_000);
    schedule();
  }
  return () => {
    listeners.delete(listener);
    if (listeners.size === 0 && timer) {
      clearTimeout(timer);
      timer = null;
    }
  };
}

const clientMinute = () => minute || Math.floor(Date.now() / 60_000);
const serverMinute = () => 0;

/** The visitor's own time, to the minute. Null in the server render, so it
 *  never guesses a timezone. */
export function useNow(): Date | null {
  const m = useSyncExternalStore(subscribe, clientMinute, serverMinute);
  return m === 0 ? null : new Date();
}

/** macOS's menu bar clock: "Mon 3:42 PM", in the visitor's locale. */
export function menuBarClock(d: Date | null): string {
  if (!d) return " ";
  const day = d.toLocaleDateString(undefined, { weekday: "short" });
  const time = d.toLocaleTimeString(undefined, { hour: "numeric", minute: "2-digit" });
  return `${day} ${time}`;
}

/** Hun's panel date (weekday, day and month): "Monday, 2 November". */
export function panelDate(d: Date | null): string {
  if (!d) return " ";
  return d.toLocaleDateString(undefined, { weekday: "long", day: "numeric", month: "long" });
}
