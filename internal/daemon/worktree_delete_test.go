package daemon

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/sourabhrathourr/hun/internal/config"
)

func gitIn(t *testing.T, dir string, arguments ...string) string {
	t.Helper()
	command := exec.Command("git", append([]string{"-c", "user.name=t", "-c", "user.email=t@t", "-c", "init.defaultBranch=main"}, arguments...)...)
	command.Dir = dir
	output, err := command.CombinedOutput()
	if err != nil {
		t.Fatalf("git %v: %v\n%s", arguments, err, output)
	}
	return strings.TrimSpace(string(output))
}

// newWorktreeFixture makes a repository with one linked worktree on branch,
// registered with a fresh manager as "repo-wt".
func newWorktreeFixture(t *testing.T, branch string) (*Manager, string, string) {
	t.Helper()
	t.Setenv("HOME", t.TempDir())
	m, err := NewManager()
	if err != nil {
		t.Fatalf("new manager: %v", err)
	}
	t.Cleanup(m.Shutdown)

	repo := filepath.Join(t.TempDir(), "repo")
	if err := os.MkdirAll(repo, 0o755); err != nil {
		t.Fatal(err)
	}
	gitIn(t, repo, "init")
	if err := os.WriteFile(filepath.Join(repo, "README"), []byte("hi\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	gitIn(t, repo, "add", ".")
	gitIn(t, repo, "commit", "-m", "first")
	worktree := filepath.Join(repo, ".claude", "worktrees", "wt")
	gitIn(t, repo, "worktree", "add", "-b", branch, worktree)
	m.st.Register("repo-wt", worktree)
	main, ok := config.MainCheckout(worktree)
	if !ok {
		t.Fatalf("expected %s to be a worktree", worktree)
	}
	return m, main, worktree
}

func knownPullRequests(m *Manager, repo string, byBranch map[string]PullRequestRef) {
	m.prs.mu.Lock()
	defer m.prs.mu.Unlock()
	m.prs.repos = map[string]*repoPullRequests{repo: {byBranch: byBranch, fetchedAt: time.Now()}}
}

func branchExists(t *testing.T, repo, branch string) bool {
	return gitIn(t, repo, "branch", "--list", branch) != ""
}

func TestDeleteWorktreeRefusesUncommittedChangesUnlessForced(t *testing.T) {
	m, main, worktree := newWorktreeFixture(t, "feat-x")
	knownPullRequests(m, main, nil)
	if err := os.WriteFile(filepath.Join(worktree, "notes.txt"), []byte("wip\n"), 0o644); err != nil {
		t.Fatal(err)
	}

	d := &Daemon{manager: m}
	resp := d.HandleRequest(Request{Action: "delete_worktree", Project: "repo-wt"})
	if resp.OK || !strings.Contains(resp.Error, "1 uncommitted change") {
		t.Fatalf("expected refusal for uncommitted change, got %+v", resp)
	}
	if _, err := os.Stat(worktree); err != nil {
		t.Fatalf("worktree should still be there: %v", err)
	}

	resp = d.HandleRequest(Request{Action: "delete_worktree", Project: "repo-wt", Force: true})
	if !resp.OK {
		t.Fatalf("forced delete: %s", resp.Error)
	}
	if _, err := os.Stat(worktree); !os.IsNotExist(err) {
		t.Fatalf("worktree folder should be gone, stat err: %v", err)
	}
	if _, ok := m.ProjectPath("repo-wt"); ok {
		t.Fatal("worktree should no longer be registered")
	}
	if !branchExists(t, main, "feat-x") {
		t.Fatal("branch without a merged pull request should be kept")
	}
}

func TestDeleteWorktreeDeletesBranchOnlyWhenMerged(t *testing.T) {
	m, main, worktree := newWorktreeFixture(t, "feat-y")
	head := gitIn(t, main, "rev-parse", "feat-y")
	knownPullRequests(m, main, map[string]PullRequestRef{"feat-y": {Number: 7, State: "merged", Head: head}})

	result, err := m.DeleteWorktree("repo-wt", false)
	if err != nil {
		t.Fatalf("delete: %v", err)
	}
	if !result.BranchDeleted || result.Branch != "feat-y" {
		t.Fatalf("expected feat-y deleted, got %+v", result)
	}
	if branchExists(t, main, "feat-y") {
		t.Fatal("merged branch should be deleted")
	}
	if _, err := os.Stat(worktree); !os.IsNotExist(err) {
		t.Fatalf("worktree folder should be gone, stat err: %v", err)
	}
}

func TestDeleteWorktreeKeepsMergedBranchWithNewerCommits(t *testing.T) {
	m, main, worktree := newWorktreeFixture(t, "feat-n")
	merged := gitIn(t, main, "rev-parse", "feat-n")
	knownPullRequests(m, main, map[string]PullRequestRef{"feat-n": {Number: 9, State: "merged", Head: merged}})
	if err := os.WriteFile(filepath.Join(worktree, "later.txt"), []byte("after merge\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	gitIn(t, worktree, "add", ".")
	gitIn(t, worktree, "commit", "-m", "after merge")

	result, err := m.DeleteWorktree("repo-wt", false)
	if err != nil {
		t.Fatalf("delete: %v", err)
	}
	if result.BranchDeleted || !branchExists(t, main, "feat-n") {
		t.Fatalf("a branch with commits the PR doesn't have should be kept, got %+v", result)
	}
}

func TestDeleteWorktreeKeepsBranchWithOpenPullRequest(t *testing.T) {
	m, main, _ := newWorktreeFixture(t, "feat-z")
	knownPullRequests(m, main, map[string]PullRequestRef{"feat-z": {Number: 8, State: "open"}})

	result, err := m.DeleteWorktree("repo-wt", false)
	if err != nil {
		t.Fatalf("delete: %v", err)
	}
	if result.BranchDeleted || !branchExists(t, main, "feat-z") {
		t.Fatalf("branch with an open pull request should be kept, got %+v", result)
	}
}

func TestDeleteWorktreeRefusesMainCheckout(t *testing.T) {
	m, main, _ := newWorktreeFixture(t, "feat-m")
	m.st.Register("repo", main)
	if _, err := m.DeleteWorktree("repo", true); err == nil || !strings.Contains(err.Error(), "not a git worktree") {
		t.Fatalf("expected refusal for the main checkout, got %v", err)
	}
	if _, err := os.Stat(main); err != nil {
		t.Fatalf("main checkout must be untouched: %v", err)
	}
}

func TestPullRequestsByBranch(t *testing.T) {
	output := []byte(`[
		{"number": 10, "state": "CLOSED", "isDraft": false, "url": "u10", "headRefName": "a"},
		{"number": 12, "state": "MERGED", "isDraft": false, "url": "u12", "headRefName": "a", "headRefOid": "h12"},
		{"number": 13, "state": "CLOSED", "isDraft": false, "url": "u13", "headRefName": "a"},
		{"number": 20, "state": "OPEN", "isDraft": true, "url": "u20", "headRefName": "b"},
		{"number": 21, "state": "CLOSED", "isDraft": false, "url": "u21", "headRefName": "c"},
		{"number": 22, "state": "CLOSED", "isDraft": false, "url": "u22", "headRefName": "c"},
		{"number": 30, "state": "MERGED", "isDraft": false, "url": "u30", "headRefName": "d"},
		{"number": 31, "state": "OPEN", "isDraft": false, "url": "u31", "headRefName": "d"}
	]`)
	got, err := pullRequestsByBranch(output)
	if err != nil {
		t.Fatal(err)
	}
	want := map[string]PullRequestRef{
		"a": {Number: 12, State: "merged", URL: "u12", Head: "h12"},
		"b": {Number: 20, State: "draft", URL: "u20"},
		"c": {Number: 22, State: "closed", URL: "u22"},
		"d": {Number: 31, State: "open", URL: "u31"},
	}
	for branch, pr := range want {
		if got[branch] != pr {
			t.Errorf("%s: got %+v, want %+v", branch, got[branch], pr)
		}
	}
}

func TestPullRequestLookupFillsInTheBackground(t *testing.T) {
	calls := 0
	previous := listPullRequests
	listPullRequests = func(repo string) (map[string]PullRequestRef, error) {
		calls++
		return map[string]PullRequestRef{"feat": {Number: 1, State: "merged"}}, nil
	}
	t.Cleanup(func() { listPullRequests = previous })

	var cache pullRequestCache
	if pr := cache.lookup("/repo", "feat"); pr != nil {
		t.Fatalf("first lookup shouldn't wait for GitHub, got %+v", pr)
	}
	deadline := time.Now().Add(2 * time.Second)
	for {
		if pr := cache.lookup("/repo", "feat"); pr != nil {
			if pr.State != "merged" {
				t.Fatalf("got %+v", pr)
			}
			break
		}
		if time.Now().After(deadline) {
			t.Fatal("pull request never arrived")
		}
		time.Sleep(10 * time.Millisecond)
	}
	cache.lookup("/repo", "other")
	if calls != 1 {
		t.Fatalf("a fresh repository shouldn't be asked again, asked %d times", calls)
	}
}

func TestApplyChecks(t *testing.T) {
	byBranch := map[string]PullRequestRef{
		"red":     {Number: 1, State: "open"},
		"waiting": {Number: 2, State: "draft"},
		"green":   {Number: 3, State: "open"},
		"status":  {Number: 4, State: "open"},
		"none":    {Number: 5, State: "open"},
		"merged":  {Number: 6, State: "merged"},
	}
	applyChecks(byBranch, []byte(`[
		{"number": 1, "statusCheckRollup": [
			{"status": "COMPLETED", "conclusion": "SUCCESS"},
			{"status": "COMPLETED", "conclusion": "FAILURE"},
			{"status": "IN_PROGRESS", "conclusion": ""}]},
		{"number": 2, "statusCheckRollup": [
			{"status": "COMPLETED", "conclusion": "SUCCESS"},
			{"status": "QUEUED", "conclusion": ""}]},
		{"number": 3, "statusCheckRollup": [
			{"status": "COMPLETED", "conclusion": "SUCCESS"},
			{"status": "COMPLETED", "conclusion": "SKIPPED"},
			{"status": "COMPLETED", "conclusion": "CANCELLED"}]},
		{"number": 4, "statusCheckRollup": [{"state": "ERROR"}]},
		{"number": 5, "statusCheckRollup": []},
		{"number": 6, "statusCheckRollup": [{"status": "COMPLETED", "conclusion": "FAILURE"}]}
	]`))
	want := map[string]string{"red": "failing", "waiting": "pending", "green": "passing", "status": "failing", "none": "", "merged": ""}
	for branch, checks := range want {
		if got := byBranch[branch].Checks; got != checks {
			t.Errorf("%s: got %q, want %q", branch, got, checks)
		}
	}
}
