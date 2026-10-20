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

func TestLogManagerClearBuffersKeepsOtherProjects(t *testing.T) {
	t.Setenv("HOME", t.TempDir())
	lm, err := NewLogManager()
	if err != nil {
		t.Fatalf("new log manager: %v", err)
	}
	defer lm.Close()
	for _, line := range []LogLine{
		{Project: "proj", Service: "a", Text: "a"},
		{Project: "proj", Service: "b", Text: "b"},
		{Project: "other", Service: "a", Text: "other"},
	} {
		line.Timestamp = time.Now()
		lm.WriteLog(line)
	}

	lm.ClearBuffers("proj", "a")
	if got := lm.GetLines("proj", "", 100); len(got) != 1 || got[0].Service != "b" {
		t.Fatalf("after clearing one service: %+v", got)
	}

	lm.ClearBuffers("proj", "")
	if got := lm.GetLines("proj", "", 100); len(got) != 0 {
		t.Fatalf("after clearing the project: %+v", got)
	}
	if got := lm.GetLines("other", "", 100); len(got) != 1 {
		t.Fatalf("another project's logs were cleared: %+v", got)
	}

	lm.WriteLog(LogLine{Project: "proj", Service: "a", Text: "fresh", Timestamp: time.Now()})
	if got := lm.GetLines("proj", "a", 100); len(got) != 1 || got[0].Text != "fresh" {
		t.Fatalf("new lines after clearing: %+v", got)
	}
}
