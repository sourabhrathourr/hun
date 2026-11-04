package daemon

import (
	"math"
	"testing"
	"time"
)

func TestOpenFileTarget(t *testing.T) {
	cases := []struct {
		name             string
		hard, perProcess uint64
		want             uint64
	}{
		{"unlimited hard limit, macOS ceiling", math.MaxInt64, 61440, 61440},
		{"hard limit below the ceiling", 10240, 61440, 10240},
		{"no ceiling known", 524288, 0, 524288},
		{"huge hard limit is capped", 1 << 30, 0, maxOpenFiles},
		{"unlimited and no ceiling", math.MaxUint64, 0, maxOpenFiles},
	}
	for _, c := range cases {
		if got := openFileTarget(c.hard, c.perProcess); got != c.want {
			t.Errorf("%s: openFileTarget(%d, %d) = %d, want %d", c.name, c.hard, c.perProcess, got, c.want)
		}
	}
}

func TestRestartDelay(t *testing.T) {
	want := []int{1, 2, 4, 8, 10, 10, 10}
	for i, w := range want {
		if got := restartDelay(i + 1).Seconds(); int(got) != w {
			t.Errorf("restartDelay(%d) = %vs, want %ds", i+1, got, w)
		}
	}
}

func TestRecentCrashes(t *testing.T) {
	now := time.Date(2026, 11, 5, 10, 0, 0, 0, time.UTC)
	crashes := []time.Time{now.Add(-3 * crashWindow), now.Add(-crashWindow / 2), now}
	if got := recentCrashes(crashes, now); len(got) != 2 {
		t.Fatalf("recentCrashes kept %d, want 2", len(got))
	}
}

func TestLooksLikeFileLimit(t *testing.T) {
	yes := []string{
		"Watchpack Error (watcher): Error: EMFILE: too many open files, watch",
		"OSError: [Errno 24] Too many open files",
	}
	for _, line := range yes {
		if !looksLikeFileLimit(line) {
			t.Errorf("missed %q", line)
		}
	}
	if looksLikeFileLimit("compiled successfully in 1.2s") {
		t.Error("flagged an ordinary line")
	}
}
