package cli

import (
	"bytes"
	"strings"
	"testing"
)

func TestSetVersionInfoUpdatesShortVersionOutput(t *testing.T) {
	origVersion := versionStr
	origCommit := commitStr
	origRootVersion := rootCmd.Version

	t.Cleanup(func() {
		versionStr = origVersion
		commitStr = origCommit
		rootCmd.Version = origRootVersion
		rootCmd.SetArgs(nil)
		rootCmd.SetOut(nil)
		rootCmd.SetErr(nil)
	})

	SetVersionInfo("v1.2.3", "abc123")

	var stdout bytes.Buffer
	rootCmd.SetOut(&stdout)
	rootCmd.SetErr(&stdout)
	rootCmd.SetArgs([]string{"--version"})

	if err := rootCmd.Execute(); err != nil {
		t.Fatalf("execute --version: %v", err)
	}

	got := strings.TrimSpace(stdout.String())
	want := "hun.sh v1.2.3"
	if got != want {
		t.Fatalf("version output = %q, want %q", got, want)
	}
}
