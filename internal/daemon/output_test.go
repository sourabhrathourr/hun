package daemon

import (
	"bufio"
	"encoding/json"
	"io"
	"net"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"testing"
	"time"
)

func TestLongOutputLinesAreTruncatedAndReadingContinues(t *testing.T) {
	var mu sync.Mutex
	var lines []string
	p := &Process{onOutput: func(line string, _ bool) {
		mu.Lock()
		lines = append(lines, line)
		mu.Unlock()
	}}

	r, w := io.Pipe()
	done := make(chan struct{})
	go func() {
		p.scanOutput(r, false)
		close(done)
	}()

	huge := strings.Repeat("x", 300*1024)
	writeDone := make(chan error, 1)
	go func() {
		_, err := io.WriteString(w, "before\r\n"+huge+"\nafter\nlast without newline")
		w.Close()
		writeDone <- err
	}()

	select {
	case err := <-writeDone:
		if err != nil {
			t.Fatalf("write: %v", err)
		}
	case <-time.After(5 * time.Second):
		t.Fatal("the writer blocked: output stopped being read after the long line")
	}
	<-done

	mu.Lock()
	defer mu.Unlock()
	if len(lines) != 4 {
		t.Fatalf("got %d lines, want 4", len(lines))
	}
	if lines[0] != "before" {
		t.Fatalf("line 1 = %q, want the \\r dropped", lines[0])
	}
	if !strings.HasPrefix(lines[1], strings.Repeat("x", maxOutputLine)) ||
		!strings.HasSuffix(lines[1], "[hun: line truncated, 241664 more bytes]") {
		t.Fatalf("long line not truncated as expected: %d bytes, ends %q", len(lines[1]), lines[1][len(lines[1])-48:])
	}
	if lines[2] != "after" || lines[3] != "last without newline" {
		t.Fatalf("lines after the long one = %q, %q", lines[2], lines[3])
	}
}

func TestSubscribersReceiveABurstInOrder(t *testing.T) {
	d, m, _ := newProfileDaemon(t)
	server, client := net.Pipe()
	defer client.Close()
	go d.handleSubscribe(server, Request{Action: "subscribe", Project: "shop"})

	reader := bufio.NewReader(client)
	if _, err := reader.ReadBytes('\n'); err != nil { // the OK response
		t.Fatalf("read ack: %v", err)
	}

	const total = 5000
	go func() {
		for i := 0; i < total; i++ {
			// Broadcast drops lines for a slow reader, so pace the burst to
			// the channel rather than the socket.
			for {
				sub := firstSubscriber(m)
				if sub == nil || len(sub.Ch) < cap(sub.Ch)-1 {
					break
				}
				time.Sleep(time.Millisecond)
			}
			m.subscribers.Broadcast(LogLine{Project: "shop", Service: "web", Text: strconv.Itoa(i)})
		}
	}()

	client.SetReadDeadline(time.Now().Add(10 * time.Second))
	for i := 0; i < total; i++ {
		raw, err := reader.ReadBytes('\n')
		if err != nil {
			t.Fatalf("line %d: %v", i, err)
		}
		var line LogLine
		if err := json.Unmarshal(raw, &line); err != nil {
			t.Fatalf("line %d: %v", i, err)
		}
		if line.Text != strconv.Itoa(i) {
			t.Fatalf("line %d = %q, out of order", i, line.Text)
		}
	}
}

func firstSubscriber(m *Manager) *Subscriber {
	m.subscribers.mu.Lock()
	defer m.subscribers.mu.Unlock()
	for _, sub := range m.subscribers.subscribers {
		return sub
	}
	return nil
}

func TestSnapshotConfigIsReparsedOnlyWhenTheFileChanges(t *testing.T) {
	_, m, projectDir := newProfileDaemon(t)

	first, err := m.cachedProjectConfig(projectDir)
	if err != nil {
		t.Fatalf("load: %v", err)
	}
	again, _ := m.cachedProjectConfig(projectDir)
	if again != first {
		t.Fatalf("an unchanged file was parsed again")
	}

	path := filepath.Join(projectDir, ".hun.yml")
	if err := os.WriteFile(path, []byte("name: renamed\nservices:\n  web:\n    cmd: sleep 30\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	later := time.Now().Add(2 * time.Second)
	if err := os.Chtimes(path, later, later); err != nil {
		t.Fatal(err)
	}
	updated, err := m.cachedProjectConfig(projectDir)
	if err != nil {
		t.Fatalf("reload: %v", err)
	}
	if updated == first || updated.Name != "renamed" {
		t.Fatalf("an edited file was not re-parsed: name %q", updated.Name)
	}

	if err := os.WriteFile(path, []byte("name: broken\nservices: {}\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	if _, err := m.cachedProjectConfig(projectDir); err == nil {
		t.Fatalf("an invalid file should report its error")
	}
}
