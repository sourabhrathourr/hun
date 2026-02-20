package tui

import (
	"fmt"
	"io"
	"os"
	"os/exec"
	"runtime"
	"strings"

	osc52 "github.com/aymanbagabas/go-osc52/v2"
)

type clipboardCommand struct {
	name string
	args []string
}

var (
	osc52Out      = io.Writer(os.Stderr)
	clipboardExec = func(name string, args ...string) *exec.Cmd {
		return exec.Command(name, args...)
	}
	clipboardCommands = defaultClipboardCommands
)

func copyToClipboard(text string) error {
	if strings.TrimSpace(text) == "" {
		return fmt.Errorf("empty selection")
	}

	oscErr := copyWithOSC52(text)
	nativeErr := copyWithNative(text)
	if nativeErr == nil {
		return nil
	}
	if oscErr == nil {
		return nil
	}
	return fmt.Errorf("no clipboard backend available")
}

func copyWithOSC52(text string) error {
	seq := osc52.New(text)
	if os.Getenv("TMUX") != "" {
		seq = seq.Tmux()
	}
	if term := strings.ToLower(os.Getenv("TERM")); strings.Contains(term, "screen") {
		seq = seq.Screen()
	}
	_, err := io.WriteString(osc52Out, seq.String())
	return err
}

func copyWithNative(text string) error {
	for _, cmd := range clipboardCommands() {
		if cmd.name == "" {
			continue
		}
		c := clipboardExec(cmd.name, cmd.args...)
		c.Stdin = strings.NewReader(text)
		if err := c.Run(); err == nil {
			return nil
		}
	}
	return fmt.Errorf("native clipboard unavailable")
}

func defaultClipboardCommands() []clipboardCommand {
	switch runtime.GOOS {
	case "darwin":
		return []clipboardCommand{{name: "pbcopy"}}
	case "windows":
		return []clipboardCommand{{name: "clip"}}
	default:
		return []clipboardCommand{
			{name: "wl-copy"},
			{name: "xclip", args: []string{"-selection", "clipboard"}},
			{name: "xsel", args: []string{"--clipboard", "--input"}},
		}
	}
}
