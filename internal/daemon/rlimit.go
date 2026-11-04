package daemon

import (
	"math"
	"syscall"
)

// maxOpenFiles caps the limit Hun asks for on systems that report no limit.
const maxOpenFiles = 1 << 20

// openFileLimit is the soft limit on open files that services get; 0 until
// raiseOpenFileLimit has run.
var openFileLimit uint64

// raiseOpenFileLimit lifts the daemon's soft limit on open files as high as
// the system allows, so every service inherits a usable one. When launchd
// starts Hun (opened from Finder, Spotlight or at login) the soft limit is
// macOS's default of 256; a dev server watching more than a few hundred
// folders then fails with EMFILE. Terminals raise the limit themselves, which
// is why this only shows when Hun is opened as an app.
//
// Go raises its own limit at startup but hands child processes the original
// one, unless the program sets the limit itself with syscall.Setrlimit, as
// here.
func raiseOpenFileLimit() error {
	var limit syscall.Rlimit
	if err := syscall.Getrlimit(syscall.RLIMIT_NOFILE, &limit); err != nil {
		return err
	}
	target := openFileTarget(limit.Max, maxFilesPerProcess())
	if target < limit.Cur {
		target = limit.Cur
	}
	limit.Cur = target
	if err := syscall.Setrlimit(syscall.RLIMIT_NOFILE, &limit); err != nil {
		return err
	}
	openFileLimit = target
	return nil
}

// openFileTarget is the soft limit to ask for: the hard limit, but no more
// than the kernel allows one process (perProcess, 0 when unknown) or
// maxOpenFiles.
func openFileTarget(hard, perProcess uint64) uint64 {
	target := hard
	if target == 0 || target == math.MaxUint64 || target == math.MaxInt64 {
		target = maxOpenFiles
	}
	if perProcess > 0 && target > perProcess {
		target = perProcess
	}
	if target > maxOpenFiles {
		target = maxOpenFiles
	}
	return target
}
