package tui

import (
	"strings"
)

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

	line1 := strings.Join(keys[:len(keys)/2], "  ")
	line2 := strings.Join(keys[len(keys)/2:], "  ")

	return statusBarStyle.Width(m.width).Render(line1 + "\n" + line2)
}

func keyBind(key, desc string) string {
	return "[" + keyStyle.Render(key) + "] " + descStyle.Render(desc)
}
