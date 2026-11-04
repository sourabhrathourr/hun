//go:build !darwin

package daemon

func maxFilesPerProcess() uint64 { return 0 }
