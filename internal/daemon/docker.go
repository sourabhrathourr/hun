package daemon

import (
	"context"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"time"
)

var (
	dockerReadyTimeout      = 90 * time.Second
	dockerReadyPollInterval = 2 * time.Second
	dockerInfoTimeout       = 3 * time.Second

	checkDockerDaemon  = defaultCheckDockerDaemon
	launchDockerApp    = defaultLaunchDockerApp
	sleepBeforeRecheck = time.Sleep
)

func ensureDockerReadyForCommand(command string, emit func(string)) error {
	if !commandNeedsDocker(command) {
		return nil
	}

	if err := checkDockerDaemonWithTimeout(); err == nil {
		return nil
	}

	if runtime.GOOS != "darwin" {
		return errors.New("Docker daemon is not running; start Docker and retry")
	}

	emitDockerLine(emit, "Docker isn't running; starting it in the background...")
	if err := launchDockerApp(); err != nil {
		return fmt.Errorf("starting Docker: %w", err)
	}

	deadline := time.Now().Add(dockerReadyTimeout)
	for {
		if err := checkDockerDaemonWithTimeout(); err == nil {
			emitDockerLine(emit, "Docker is ready.")
			return nil
		} else if time.Now().After(deadline) {
			return fmt.Errorf("Docker was started, but it did not become ready within %s: %w", dockerReadyTimeout.Round(time.Second), err)
		}
		sleepBeforeRecheck(dockerReadyPollInterval)
	}
}

func commandNeedsDocker(command string) bool {
	normalized := strings.NewReplacer(
		"&&", " && ",
		"||", " || ",
		";", " ; ",
		"|", " | ",
		"(", " ( ",
		")", " ) ",
	).Replace(command)

	expectingCommand := true
	for _, token := range strings.Fields(normalized) {
		if isShellCommandBoundary(token) {
			expectingCommand = true
			continue
		}
		if !expectingCommand {
			continue
		}
		if isShellAssignment(token) || isCommandWrapper(token) || isShellKeyword(token) || strings.HasPrefix(token, "-") {
			continue
		}
		if isDockerExecutableToken(token) {
			return true
		}
		expectingCommand = false
	}
	return false
}

func checkDockerDaemonWithTimeout() error {
	ctx, cancel := context.WithTimeout(context.Background(), dockerInfoTimeout)
	defer cancel()
	return checkDockerDaemon(ctx)
}

func defaultCheckDockerDaemon(ctx context.Context) error {
	dockerPath, err := findDockerExecutable()
	if err != nil {
		return err
	}

	cmd := exec.CommandContext(ctx, dockerPath, "info")
	cmd.Env = withDeveloperEnvironment(os.Environ())
	if output, err := cmd.CombinedOutput(); err != nil {
		message := strings.TrimSpace(string(output))
		if message == "" {
			return err
		}
		return fmt.Errorf("%w: %s", err, message)
	}
	return nil
}

func findDockerExecutable() (string, error) {
	env := withDeveloperEnvironment(os.Environ())
	path := envValue(env, "PATH")
	if dockerPath, err := exec.LookPath("docker"); err == nil {
		return dockerPath, nil
	}
	for _, dir := range splitPath(path) {
		candidate := filepath.Join(dir, "docker")
		if isExecutableFile(candidate) {
			return candidate, nil
		}
	}
	return "", errors.New("docker executable not found")
}

// defaultLaunchDockerApp starts Docker Desktop without bringing it in front
// of the user's work. Its own CLI starts the engine in the background; older
// versions without that command are opened in the background instead.
// Whether Docker shows its dashboard is Docker's own setting.
func defaultLaunchDockerApp() error {
	if runtime.GOOS != "darwin" {
		return errors.New("Docker Desktop auto-start is only supported on macOS")
	}
	if dockerPath, err := findDockerExecutable(); err == nil {
		cmd := exec.Command(dockerPath, "desktop", "start", "--detach")
		cmd.Env = withDeveloperEnvironment(os.Environ())
		if cmd.Run() == nil {
			return nil
		}
	}
	if _, err := exec.LookPath("open"); err != nil {
		return err
	}
	if err := exec.Command("open", "-g", "-j", "-a", "Docker").Run(); err == nil {
		return nil
	}
	return exec.Command("open", "-g", "-j", "/Applications/Docker.app").Run()
}

func isExecutableFile(path string) bool {
	info, err := os.Stat(path)
	return err == nil && !info.IsDir() && info.Mode().Perm()&0111 != 0
}

func emitDockerLine(emit func(string), line string) {
	if emit != nil {
		emit(line)
	}
}

func isShellCommandBoundary(token string) bool {
	switch token {
	case "&&", "||", ";", "|", "(", ")":
		return true
	default:
		return false
	}
}

func isShellAssignment(token string) bool {
	if strings.HasPrefix(token, "=") {
		return false
	}
	equals := strings.IndexByte(token, '=')
	if equals <= 0 {
		return false
	}
	key := token[:equals]
	for _, r := range key {
		if r != '_' && (r < 'A' || r > 'Z') && (r < 'a' || r > 'z') && (r < '0' || r > '9') {
			return false
		}
	}
	return true
}

func isCommandWrapper(token string) bool {
	switch token {
	case "command", "env", "exec", "nohup", "sudo":
		return true
	default:
		return false
	}
}

// isShellKeyword reports keywords that precede a command, as in
// `if ...; then docker compose up; fi`.
func isShellKeyword(token string) bool {
	switch token {
	case "if", "then", "else", "elif", "do", "while", "until", "!", "{":
		return true
	default:
		return false
	}
}

func isDockerExecutableToken(token string) bool {
	base := filepath.Base(strings.Trim(token, `"'`))
	return base == "docker" || base == "docker-compose"
}
