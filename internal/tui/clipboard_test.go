package tui

import (
	"bytes"
	"fmt"
	"runtime"
	"testing"
)

type failingWriter struct{}

func (f failingWriter) Write(p []byte) (int, error) {
	return 0, fmt.Errorf("write failed")
}

func TestCopyToClipboardOSC52Success(t *testing.T) {
	origOut := osc52Out
	origCommands := clipboardCommands
	origExec := clipboardExec
	t.Cleanup(func() {
		osc52Out = origOut
		clipboardCommands = origCommands
		clipboardExec = origExec
	})

	osc52Out = &bytes.Buffer{}
	clipboardCommands = func() []clipboardCommand {
		return []clipboardCommand{{name: "definitely-missing-binary"}}
	}

	if err := copyToClipboard("hello"); err != nil {
		t.Fatalf("copyToClipboard() error = %v, want nil", err)
	}
}

func TestCopyToClipboardFallsBackToNative(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("shell command differs on windows")
	}

	origOut := osc52Out
	origCommands := clipboardCommands
	origExec := clipboardExec
	t.Cleanup(func() {
		osc52Out = origOut
		clipboardCommands = origCommands
		clipboardExec = origExec
	})

	osc52Out = failingWriter{}
	clipboardCommands = func() []clipboardCommand {
		return []clipboardCommand{{name: "sh", args: []string{"-c", "cat >/dev/null"}}}
	}

	if err := copyToClipboard("hello"); err != nil {
		t.Fatalf("copyToClipboard() error = %v, want nil", err)
	}
}

func TestCopyToClipboardFailsWithoutBackends(t *testing.T) {
	origOut := osc52Out
	origCommands := clipboardCommands
	origExec := clipboardExec
	t.Cleanup(func() {
		osc52Out = origOut
		clipboardCommands = origCommands
		clipboardExec = origExec
	})

	osc52Out = failingWriter{}
	clipboardCommands = func() []clipboardCommand {
		return []clipboardCommand{{name: "definitely-missing-binary"}}
	}

	if err := copyToClipboard("hello"); err == nil {
		t.Fatal("copyToClipboard() error = nil, want non-nil")
	}
}
