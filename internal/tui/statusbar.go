package tui

import (
	"strings"
)

type statusBarModel struct {
	mode  string
	width int
}

func (m statusBarModel) View() string {
	var keys []string

	if m.mode == "focus" {
		keys = []string{
			keyBind("\u2191\u2193", "service"),
			keyBind("r", "restart"),
			keyBind("c", "copy"),
			keyBind("/", "search"),
			keyBind("p", "picker"),
			keyBind("R", "restart project"),
			keyBind("m", "multitask"),
			keyBind("q", "quit"),
		}
	} else {
		keys = []string{
			keyBind("tab", "project"),
			keyBind("\u2191\u2193", "service"),
			keyBind("r", "restart"),
			keyBind("c", "copy"),
			keyBind("/", "search"),
			keyBind("s", "stop"),
			keyBind("p", "picker"),
			keyBind("R", "restart project"),
			keyBind("f", "focus mode"),
			keyBind("q", "quit"),
		}
	}

	line1 := strings.Join(keys[:len(keys)/2], "  ")
	line2 := strings.Join(keys[len(keys)/2:], "  ")

	return statusBarStyle.Width(m.width).Render(line1 + "\n" + line2)
}

func keyBind(key, desc string) string {
	return "[" + keyStyle.Render(key) + "] " + descStyle.Render(desc)
}
