package main

import (
	"os"

	"github.com/sourabhrathourr/hun/internal/cli"
)

var (
	version = "dev"
	commit  = "none"
)

func main() {
	cli.SetVersionInfo(version, commit)
	if err := cli.Execute(); err != nil {
		os.Exit(1)
	}
}
