package tui

import "github.com/charmbracelet/lipgloss"

type statusBarModel struct {
	mode          string
	width         int
	activePane    string
	selectionMode bool
}

func (m statusBarModel) View() string {
	movement := "service"
	if m.activePane == paneLogs {
		movement = "log"
	}
	keys := []string{
		keyBind("\u2190\u2192", "pane"),
		keyBind("\u2191\u2193", movement),
		keyBind("u/d", "fast scroll"),
		keyBind("w", "wrap"),
		keyBind("v", "select"),
		keyBind("c/y", "copy"),
		keyBind("/", "search"),
		keyBind("p", "picker"),
		keyBind("r", "restart"),
		keyBind("R", "restart project"),
		keyBind("s", "stop project"),
		keyBind("x", "stop service"),
	}
	if m.activePane == paneLogs {
		keys = append(keys, keyBind("l", "live"))
	}
	if m.mode == "multitask" {
		keys = append(keys, keyBind("tab", "project"))
		keys = append(keys, keyBind("f", "focus mode"))
	} else {
		keys = append(keys, keyBind("m", "multitask"))
	}
	keys = append(keys, keyBind("q", "quit"))
	if m.selectionMode {
		keys = append(keys, keyBind("enter", "copy range"))
	}

	contentWidth := m.width - 2 // status bar has horizontal padding
	if contentWidth < 1 {
		contentWidth = 1
	}
	line1, used := fitStatusLine(keys, contentWidth)
	line2, _ := fitStatusLine(keys[used:], contentWidth)

	return statusBarStyle.Width(m.width).Render(line1 + "\n" + line2)
}

func fitStatusLine(keys []string, maxWidth int) (string, int) {
	if len(keys) == 0 {
		return "", 0
	}
	sep := "  "
	line := ""
	used := 0
	for i, key := range keys {
		candidate := key
		if line != "" {
			candidate = line + sep + key
		}
		if lipgloss.Width(candidate) > maxWidth {
			break
		}
		line = candidate
		used = i + 1
	}
	if used == 0 {
		return keys[0], 1
	}
	return line, used
}

func keyBind(key, desc string) string {
	return "[" + keyStyle.Render(key) + "] " + descStyle.Render(desc)
}
