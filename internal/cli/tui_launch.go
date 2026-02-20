package cli

import (
	"fmt"
	"os"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/sourabhrathourr/hun/internal/client"
	"github.com/sourabhrathourr/hun/internal/tui"
)

func launchTUI(multi bool) error {
	c, err := client.New()
	if err != nil {
		return err
	}
	if err := c.EnsureDaemon(); err != nil {
		fmt.Fprintf(os.Stderr, "Warning: could not start daemon: %v\n", err)
	}

	m := tui.New(multi)
	p := tea.NewProgram(m, tea.WithAltScreen(), tea.WithMouseCellMotion())
	_, err = p.Run()
	return err
}
