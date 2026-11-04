package daemon

import (
	"os"
	"syscall"
	"time"
)

// createdAt is when the folder at path was created (its birth time), or
// zero if it can't be read.
func createdAt(path string) time.Time {
	info, err := os.Stat(path)
	if err != nil {
		return time.Time{}
	}
	if st, ok := info.Sys().(*syscall.Stat_t); ok {
		return time.Unix(st.Birthtimespec.Sec, st.Birthtimespec.Nsec)
	}
	return info.ModTime()
}
