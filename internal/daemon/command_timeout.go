package daemon

import (
	"context"
	"os/exec"
	"time"
)

// Deadlines for the outside commands the daemon runs while starting,
// stopping or checking services. Run, Stop and Restart take turns, so a
// command that never returns (a wedged Docker Desktop, an lsof stuck on a
// dead mount) would leave every later action waiting until Hun restarted.
// With a deadline it fails instead, and the next action can go ahead.
const (
	quickCommandTimeout = 5 * time.Second  // lsof, ps, git: normally milliseconds
	openCommandTimeout  = 10 * time.Second // open -a Docker
	dockerStartTimeout  = 20 * time.Second // docker desktop start --detach
)

// commandWithTimeout is exec.Command with a deadline: the command is killed
// once it passes, and Wait gives up on its output soon after, even if
// something it started still holds the pipes. Call cancel when done.
func commandWithTimeout(timeout time.Duration, name string, args ...string) (*exec.Cmd, context.CancelFunc) {
	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	cmd := exec.CommandContext(ctx, name, args...)
	cmd.WaitDelay = time.Second
	return cmd, cancel
}
