//go:build !darwin

package daemon

import (
	"os"
	"time"
)

// createdAt approximates when the folder at path was created with its
// modification time, or zero if it can't be read.
func createdAt(path string) time.Time {
	info, err := os.Stat(path)
	if err != nil {
		return time.Time{}
	}
	return info.ModTime()
}
