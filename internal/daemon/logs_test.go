package daemon

import (
	"testing"
	"time"
)

func TestLogManagerResetServiceKeepsSiblingBuffers(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)

	lm, err := NewLogManager()
	if err != nil {
		t.Fatalf("new log manager: %v", err)
	}
	defer lm.Close()

	lm.WriteLog(LogLine{
		Project:   "proj",
		Service:   "a",
		Text:      "line-a",
		Timestamp: time.Now(),
	})
	lm.WriteLog(LogLine{
		Project:   "proj",
		Service:   "b",
		Text:      "line-b",
		Timestamp: time.Now(),
	})

	lm.ResetService("proj", "a")

	if got := lm.GetLines("proj", "a", 100); len(got) != 0 {
		t.Fatalf("expected service a logs cleared, got %d lines", len(got))
	}
	if got := lm.GetLines("proj", "b", 100); len(got) != 1 {
		t.Fatalf("expected service b logs untouched, got %d lines", len(got))
	}
}
