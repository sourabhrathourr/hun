package daemon

import (
	"strings"
	"testing"
	"time"
)

func TestSubscriberManagerEmitsDroppedWarning(t *testing.T) {
	sm := NewSubscriberManager()
	sub := sm.Subscribe("proj", "svc")
	defer sm.Unsubscribe(sub.ID)

	for i := 0; i < 300; i++ {
		sm.Broadcast(LogLine{Project: "proj", Service: "svc", Text: "line"})
	}

	// Free one slot so a subsequent broadcast can publish the warning message.
	select {
	case <-sub.Ch:
	case <-time.After(500 * time.Millisecond):
		t.Fatal("timed out draining subscriber channel")
	}

	sm.Broadcast(LogLine{Project: "proj", Service: "svc", Text: "after-overflow"})

	deadline := time.Now().Add(800 * time.Millisecond)
	for time.Now().Before(deadline) {
		select {
		case msg := <-sub.Ch:
			if strings.Contains(msg.Text, "dropped") {
				return
			}
		case <-time.After(20 * time.Millisecond):
		}
	}
	t.Fatal("timed out waiting for dropped warning")
}
