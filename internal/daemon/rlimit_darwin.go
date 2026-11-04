package daemon

import "syscall"

// maxFilesPerProcess is the kernel's per-process ceiling; setrlimit refuses
// a soft limit above it on macOS.
func maxFilesPerProcess() uint64 {
	n, err := syscall.SysctlUint32("kern.maxfilesperproc")
	if err != nil {
		return 0
	}
	return uint64(n)
}
