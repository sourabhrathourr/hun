package daemon

import (
	"encoding/json"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"github.com/sourabhrathourr/hun/internal/state"
)

func TestGitStatusReportsBranchDivergenceAndWorkingTreeChanges(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)
	repository := t.TempDir()

	runGitTest(t, repository, "init", "-b", "main")
	runGitTest(t, repository, "config", "user.name", "Hun Test")
	runGitTest(t, repository, "config", "user.email", "hun@example.test")
	writeGitTestFile(t, repository, ".hun.yml", "name: repo\nservices: {}\n")
	writeGitTestFile(t, repository, "tracked.txt", "first\n")
	runGitTest(t, repository, "add", ".hun.yml", "tracked.txt")
	runGitTest(t, repository, "commit", "-m", "Initial commit")
	writeGitTestFile(t, repository, "tracked.txt", "first\nsecond\n")
	writeGitTestFile(t, repository, "untracked.txt", "new\n")

	st, err := state.Load()
	if err != nil {
		t.Fatalf("load state: %v", err)
	}
	st.Register("repo", repository)
	if err := st.Save(); err != nil {
		t.Fatalf("save state: %v", err)
	}

	manager, err := NewManager()
	if err != nil {
		t.Fatalf("new manager: %v", err)
	}
	defer manager.Shutdown()

	response := (&Daemon{manager: manager}).HandleRequest(Request{
		Action:  "git_status",
		Project: "repo",
	})
	if !response.OK {
		t.Fatalf("git_status response error: %s", response.Error)
	}

	var status struct {
		IsRepository bool   `json:"is_repository"`
		Branch       string `json:"branch"`
		Clean        bool   `json:"clean"`
		Files        []struct {
			Path           string `json:"path"`
			IndexStatus    string `json:"index_status"`
			WorktreeStatus string `json:"worktree_status"`
			Untracked      bool   `json:"untracked"`
		} `json:"files"`
	}
	if err := json.Unmarshal(response.Data, &status); err != nil {
		t.Fatalf("unmarshal git status: %v", err)
	}
	if !status.IsRepository || status.Branch != "main" || status.Clean {
		t.Fatalf("status = %#v, want dirty main repository", status)
	}
	if len(status.Files) != 2 {
		t.Fatalf("files = %#v, want tracked and untracked changes", status.Files)
	}
	if status.Files[0].Path != "tracked.txt" ||
		status.Files[0].IndexStatus != "." ||
		status.Files[0].WorktreeStatus != "M" {
		t.Fatalf("tracked status = %#v", status.Files[0])
	}
	if status.Files[1].Path != "untracked.txt" || !status.Files[1].Untracked {
		t.Fatalf("untracked status = %#v", status.Files[1])
	}
}

func TestGitActionsExposeDiffStageCommitAndBranchSwitching(t *testing.T) {
	daemon, repository := newGitTestDaemon(t)
	writeGitTestFile(t, repository, "tracked.txt", "first\nsecond\n")

	diffResponse := daemon.HandleRequest(Request{
		Action:  "git_diff",
		Project: "repo",
		Path:    "tracked.txt",
	})
	if !diffResponse.OK {
		t.Fatalf("git_diff response error: %s", diffResponse.Error)
	}
	var diff struct {
		Content string `json:"content"`
	}
	if err := json.Unmarshal(diffResponse.Data, &diff); err != nil {
		t.Fatalf("unmarshal diff: %v", err)
	}
	if !containsLine(diff.Content, "+second") {
		t.Fatalf("diff does not contain added line:\n%s", diff.Content)
	}

	stageResponse := daemon.HandleRequest(Request{
		Action:  "git_stage",
		Project: "repo",
		Path:    "tracked.txt",
	})
	if !stageResponse.OK {
		t.Fatalf("git_stage response error: %s", stageResponse.Error)
	}

	stagedDiffResponse := daemon.HandleRequest(Request{
		Action:  "git_diff",
		Project: "repo",
		Path:    "tracked.txt",
		Staged:  true,
	})
	if !stagedDiffResponse.OK {
		t.Fatalf("staged git_diff response error: %s", stagedDiffResponse.Error)
	}
	if err := json.Unmarshal(stagedDiffResponse.Data, &diff); err != nil {
		t.Fatalf("unmarshal staged diff: %v", err)
	}
	if !containsLine(diff.Content, "+second") {
		t.Fatalf("staged diff does not contain added line:\n%s", diff.Content)
	}

	unstageResponse := daemon.HandleRequest(Request{
		Action:  "git_unstage",
		Project: "repo",
		Path:    "tracked.txt",
	})
	if !unstageResponse.OK {
		t.Fatalf("git_unstage response error: %s", unstageResponse.Error)
	}
	if output := runGitTest(t, repository, "diff", "--cached", "--name-only"); output != "" {
		t.Fatalf("cached changes after unstage = %q", output)
	}

	if response := daemon.HandleRequest(Request{
		Action:  "git_stage",
		Project: "repo",
		Path:    "tracked.txt",
	}); !response.OK {
		t.Fatalf("second git_stage response error: %s", response.Error)
	}
	if response := daemon.HandleRequest(Request{
		Action:  "git_commit",
		Project: "repo",
		Message: "Update tracked file",
	}); !response.OK {
		t.Fatalf("git_commit response error: %s", response.Error)
	}
	if subject := runGitTest(t, repository, "log", "-1", "--pretty=%s"); subject != "Update tracked file\n" {
		t.Fatalf("commit subject = %q", subject)
	}

	if response := daemon.HandleRequest(Request{
		Action:  "git_create_branch",
		Project: "repo",
		Branch:  "feature/git-ui",
	}); !response.OK {
		t.Fatalf("git_create_branch response error: %s", response.Error)
	}
	if branch := runGitTest(t, repository, "branch", "--show-current"); branch != "feature/git-ui\n" {
		t.Fatalf("current branch = %q", branch)
	}

	branchesResponse := daemon.HandleRequest(Request{
		Action:  "git_branches",
		Project: "repo",
	})
	if !branchesResponse.OK {
		t.Fatalf("git_branches response error: %s", branchesResponse.Error)
	}
	var branches []struct {
		Name    string `json:"name"`
		Current bool   `json:"current"`
	}
	if err := json.Unmarshal(branchesResponse.Data, &branches); err != nil {
		t.Fatalf("unmarshal branches: %v", err)
	}
	if len(branches) != 2 || branches[0].Name != "feature/git-ui" || !branches[0].Current {
		t.Fatalf("branches = %#v", branches)
	}

	if response := daemon.HandleRequest(Request{
		Action:  "git_switch_branch",
		Project: "repo",
		Branch:  "main",
	}); !response.OK {
		t.Fatalf("git_switch_branch response error: %s", response.Error)
	}
	if branch := runGitTest(t, repository, "branch", "--show-current"); branch != "main\n" {
		t.Fatalf("current branch after switch = %q", branch)
	}
}

func TestCappedGitOutputRetainsOnlyItsLimitAndSignalsCancellation(t *testing.T) {
	cancellations := 0
	output := cappedGitOutput{
		limit:   5,
		onLimit: func() { cancellations++ },
	}

	written, err := output.Write([]byte("123456789"))
	if err != nil {
		t.Fatalf("write capped output: %v", err)
	}
	if written != 9 {
		t.Fatalf("reported bytes written = %d, want 9", written)
	}
	if got := output.buffer.String(); got != "12345" {
		t.Fatalf("captured output = %q, want %q", got, "12345")
	}
	if !output.truncated || cancellations != 1 {
		t.Fatalf(
			"truncated = %v, cancellations = %d, want true and 1",
			output.truncated,
			cancellations,
		)
	}

	_, _ = output.Write([]byte("more"))
	if got := output.buffer.String(); got != "12345" {
		t.Fatalf("captured output after overflow = %q, want unchanged", got)
	}
	if cancellations != 1 {
		t.Fatalf("cancellations after repeated overflow = %d, want 1", cancellations)
	}
}

func TestGitRemoteActionsFetchPullAndPushThroughConfiguredRemote(t *testing.T) {
	daemon, repository := newGitTestDaemon(t)
	remote := t.TempDir()
	runGitTest(t, remote, "init", "--bare")
	runGitTest(t, repository, "remote", "add", "origin", remote)
	runGitTest(t, repository, "push", "-u", "origin", "main")
	runGitTest(t, remote, "symbolic-ref", "HEAD", "refs/heads/main")

	writeGitTestFile(t, repository, "local.txt", "from local\n")
	runGitTest(t, repository, "add", "local.txt")
	runGitTest(t, repository, "commit", "-m", "Local change")
	if response := daemon.HandleRequest(Request{
		Action:  "git_push",
		Project: "repo",
	}); !response.OK {
		t.Fatalf("git_push response error: %s", response.Error)
	}

	clone := t.TempDir()
	runGitTest(t, clone, "clone", remote, ".")
	runGitTest(t, clone, "config", "user.name", "Hun Remote")
	runGitTest(t, clone, "config", "user.email", "remote@example.test")
	writeGitTestFile(t, clone, "remote.txt", "from remote\n")
	runGitTest(t, clone, "add", "remote.txt")
	runGitTest(t, clone, "commit", "-m", "Remote change")
	runGitTest(t, clone, "push", "origin", "main")

	if response := daemon.HandleRequest(Request{
		Action:  "git_fetch",
		Project: "repo",
	}); !response.OK {
		t.Fatalf("git_fetch response error: %s", response.Error)
	}
	statusResponse := daemon.HandleRequest(Request{
		Action:  "git_status",
		Project: "repo",
	})
	var fetchedStatus GitStatus
	if err := json.Unmarshal(statusResponse.Data, &fetchedStatus); err != nil {
		t.Fatalf("unmarshal fetched status: %v", err)
	}
	if fetchedStatus.Behind != 1 {
		t.Fatalf("behind after fetch = %d, want 1", fetchedStatus.Behind)
	}

	if response := daemon.HandleRequest(Request{
		Action:  "git_pull",
		Project: "repo",
	}); !response.OK {
		t.Fatalf("git_pull response error: %s", response.Error)
	}
	if contents, err := os.ReadFile(filepath.Join(repository, "remote.txt")); err != nil ||
		string(contents) != "from remote\n" {
		t.Fatalf("pulled remote file = %q, %v", contents, err)
	}
}

func TestSwitchGitBranchRejectsAmbiguousLocalBranchFromAnotherRemote(t *testing.T) {
	_, repository := newGitTestDaemon(t)
	runGitTest(t, repository, "remote", "add", "origin", repository)
	runGitTest(t, repository, "remote", "add", "upstream", repository)
	runGitTest(t, repository, "update-ref", "refs/remotes/origin/topic", "HEAD")
	runGitTest(t, repository, "update-ref", "refs/remotes/upstream/topic", "HEAD")
	runGitTest(t, repository, "branch", "topic", "refs/remotes/origin/topic")
	runGitTest(t, repository, "config", "branch.topic.remote", "origin")
	runGitTest(t, repository, "config", "branch.topic.merge", "refs/heads/topic")

	err := switchGitBranch(repository, "upstream/topic")
	if err == nil || !strings.Contains(err.Error(), `local branch "topic" tracks "origin/topic"`) {
		t.Fatalf("switchGitBranch error = %v, want ambiguous tracking error", err)
	}
	if branch := runGitTest(t, repository, "branch", "--show-current"); branch != "main\n" {
		t.Fatalf("current branch = %q, want main unchanged", branch)
	}
}

func TestReadGitStatusDistinguishesNonRepositoryFromExecutionFailure(t *testing.T) {
	status, err := readGitStatus(t.TempDir())
	if err != nil {
		t.Fatalf("non-repository status: %v", err)
	}
	if status.IsRepository {
		t.Fatal("plain directory reported as a Git repository")
	}

	_, err = readGitStatus(filepath.Join(t.TempDir(), "missing"))
	if err == nil {
		t.Fatal("missing working directory should surface a Git execution error")
	}
}

func newGitTestDaemon(t *testing.T) (*Daemon, string) {
	t.Helper()
	home := t.TempDir()
	t.Setenv("HOME", home)
	repository := t.TempDir()

	runGitTest(t, repository, "init", "-b", "main")
	runGitTest(t, repository, "config", "user.name", "Hun Test")
	runGitTest(t, repository, "config", "user.email", "hun@example.test")
	writeGitTestFile(t, repository, ".hun.yml", "name: repo\nservices: {}\n")
	writeGitTestFile(t, repository, "tracked.txt", "first\n")
	runGitTest(t, repository, "add", ".hun.yml", "tracked.txt")
	runGitTest(t, repository, "commit", "-m", "Initial commit")

	st, err := state.Load()
	if err != nil {
		t.Fatalf("load state: %v", err)
	}
	st.Register("repo", repository)
	if err := st.Save(); err != nil {
		t.Fatalf("save state: %v", err)
	}
	manager, err := NewManager()
	if err != nil {
		t.Fatalf("new manager: %v", err)
	}
	t.Cleanup(manager.Shutdown)
	return &Daemon{manager: manager}, repository
}

func containsLine(text, expected string) bool {
	for _, line := range strings.Split(text, "\n") {
		if line == expected {
			return true
		}
	}
	return false
}

func runGitTest(t *testing.T, directory string, arguments ...string) string {
	t.Helper()
	command := exec.Command("git", arguments...)
	command.Dir = directory
	output, err := command.CombinedOutput()
	if err != nil {
		t.Fatalf("git %v: %v\n%s", arguments, err, output)
	}
	return string(output)
}

func writeGitTestFile(t *testing.T, repository, path, contents string) {
	t.Helper()
	fullPath := filepath.Join(repository, path)
	if err := os.MkdirAll(filepath.Dir(fullPath), 0o755); err != nil {
		t.Fatalf("create parent directory: %v", err)
	}
	if err := os.WriteFile(fullPath, []byte(contents), 0o644); err != nil {
		t.Fatalf("write %s: %v", path, err)
	}
}
