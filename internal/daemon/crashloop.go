package daemon

import (
	"fmt"
	"strings"
	"time"
)

// A service that keeps crashing is restarted with a growing pause between
// tries, up to maxRestartDelay, and never given up on: some servers exit on
// purpose until something they need (a database starting in Docker) is
// ready, and restarting is how they recover. Between tries it shows as
// crashed, and status counts its recent crashes, so a crash loop never looks
// like a healthy service.
const (
	crashWindow     = 2 * time.Minute
	maxRestartDelay = 10 * time.Second
	// From this many recent crashes, each new run's log opens with a note.
	crashLoopNotice = 3
)

// recentCrashes keeps the crashes within crashWindow of now.
func recentCrashes(crashes []time.Time, now time.Time) []time.Time {
	kept := crashes[:0]
	for _, at := range crashes {
		if now.Sub(at) <= crashWindow {
			kept = append(kept, at)
		}
	}
	return kept
}

// restartDelay is the pause before restarting after the nth recent crash:
// 1s, 2s, 4s, 8s, then 10s from then on.
func restartDelay(n int) time.Duration {
	if n < 1 {
		n = 1
	}
	if n > 5 {
		n = 5
	}
	delay := time.Second << (n - 1)
	if delay > maxRestartDelay {
		delay = maxRestartDelay
	}
	return delay
}

func crashLoopMessage(service string, crashes int, delay time.Duration) string {
	return fmt.Sprintf("[hun] %s has crashed %d times in the last %d minutes. Hun keeps restarting it, %d seconds after each crash.", service, crashes, int(crashWindow.Minutes()), int(delay.Seconds()))
}

// looksLikeFileLimit spots a process running out of open files.
func looksLikeFileLimit(line string) bool {
	return strings.Contains(line, "EMFILE") || strings.Contains(strings.ToLower(line), "too many open files")
}

func fileLimitHint(service string) string {
	if openFileLimit > 0 {
		return fmt.Sprintf("[hun] %s ran out of open files (EMFILE). Hun gives services a limit of %d; something in it is opening or watching more files than that.", service, openFileLimit)
	}
	return fmt.Sprintf("[hun] %s ran out of open files (EMFILE): something in it is opening or watching more files than the system allows.", service)
}
