package daemon

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"
	"time"
)

// PullRequestRef is the pull request for a worktree's branch, so the app can
// show whether it's open, merged or closed before the worktree is deleted.
type PullRequestRef struct {
	Number int    `json:"number"`
	State  string `json:"state"` // open, draft, merged or closed
	URL    string `json:"url"`
	// Checks sums up CI on an open pull request: failing, pending or
	// passing; empty when there are none or it isn't open.
	Checks string `json:"checks,omitempty"`
	// Head is the commit the pull request ends on. A merged branch is only
	// deleted while it still ends there, so nothing added since is lost.
	Head string `json:"-"`
}

// pullRequestTTL is how long a repository's pull requests are trusted
// before they're asked for again.
const pullRequestTTL = 2 * time.Minute

// pullRequestCache holds each repository's pull requests by branch. Lookups
// never wait: a stale repository is refreshed in the background and its
// badges appear on the next snapshot. The zero value is ready to use.
type pullRequestCache struct {
	mu    sync.Mutex
	repos map[string]*repoPullRequests
}

type repoPullRequests struct {
	byBranch  map[string]PullRequestRef
	fetchedAt time.Time
	fetching  bool
}

// listPullRequests asks GitHub for a repository's pull requests by branch.
// A var so tests can stand in for gh.
var listPullRequests = defaultListPullRequests

// lookup returns the pull request for branch in the repository at repo, or
// nil if there's none or it isn't known yet.
func (c *pullRequestCache) lookup(repo, branch string) *PullRequestRef {
	if repo == "" || branch == "" {
		return nil
	}
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.repos == nil {
		c.repos = make(map[string]*repoPullRequests)
	}
	entry := c.repos[repo]
	if entry == nil {
		entry = &repoPullRequests{}
		c.repos[repo] = entry
	}
	if !entry.fetching && time.Since(entry.fetchedAt) > pullRequestTTL {
		entry.fetching = true
		go c.refresh(repo)
	}
	if pr, ok := entry.byBranch[branch]; ok {
		return &pr
	}
	return nil
}

func (c *pullRequestCache) refresh(repo string) {
	byBranch, err := listPullRequests(repo)
	c.mu.Lock()
	defer c.mu.Unlock()
	entry := c.repos[repo]
	entry.fetching = false
	entry.fetchedAt = time.Now()
	// Keep what was known if GitHub can't be reached this time; a repo
	// without gh, or not on GitHub, simply has no badges.
	if err == nil {
		entry.byBranch = byBranch
	}
}

type ghPullRequest struct {
	Number      int    `json:"number"`
	State       string `json:"state"`
	IsDraft     bool   `json:"isDraft"`
	URL         string `json:"url"`
	HeadRefName string `json:"headRefName"`
	HeadRefOid  string `json:"headRefOid"`
}

func defaultListPullRequests(repo string) (map[string]PullRequestRef, error) {
	env := withDeveloperEnvironment(os.Environ())
	gh := lookPathIn("gh", envValue(env, "PATH"))
	if gh == "" {
		return nil, fmt.Errorf("gh not found")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 60*time.Second)
	defer cancel()
	command := exec.CommandContext(ctx, gh, "pr", "list",
		"--state", "all", "--limit", "500",
		"--json", "number,state,isDraft,url,headRefName,headRefOid")
	command.Dir = repo
	command.Env = append(env, "GH_PROMPT_DISABLED=1", "NO_COLOR=1", "GH_NO_UPDATE_NOTIFIER=1")
	output, err := command.Output()
	if err != nil {
		return nil, err
	}
	byBranch, err := pullRequestsByBranch(output)
	if err != nil {
		return nil, err
	}

	// CI only matters while a PR is open, and asking for checks on every
	// PR ever made is slow, so it's a second, smaller question.
	checks := exec.CommandContext(ctx, gh, "pr", "list",
		"--state", "open", "--limit", "200",
		"--json", "number,statusCheckRollup")
	checks.Dir = repo
	checks.Env = command.Env
	if output, err := checks.Output(); err == nil {
		applyChecks(byBranch, output)
	}
	return byBranch, nil
}

type ghCheck struct {
	Status     string `json:"status"`
	Conclusion string `json:"conclusion"`
	State      string `json:"state"`
}

// applyChecks sets each open pull request's CI summary from gh's
// statusCheckRollup: check runs (status, conclusion) and commit statuses
// (state) alike.
func applyChecks(byBranch map[string]PullRequestRef, output []byte) {
	var list []struct {
		Number int       `json:"number"`
		Checks []ghCheck `json:"statusCheckRollup"`
	}
	if json.Unmarshal(output, &list) != nil {
		return
	}
	summary := make(map[int]string, len(list))
	for _, pr := range list {
		summary[pr.Number] = summarizeChecks(pr.Checks)
	}
	for branch, pr := range byBranch {
		if pr.State != "open" && pr.State != "draft" {
			continue
		}
		if checks, ok := summary[pr.Number]; ok {
			pr.Checks = checks
			byBranch[branch] = pr
		}
	}
}

func summarizeChecks(checks []ghCheck) string {
	if len(checks) == 0 {
		return ""
	}
	pending := false
	for _, check := range checks {
		switch strings.ToUpper(check.Conclusion) {
		case "FAILURE", "TIMED_OUT", "ACTION_REQUIRED", "STARTUP_FAILURE":
			return "failing"
		}
		switch strings.ToUpper(check.State) {
		case "FAILURE", "ERROR":
			return "failing"
		case "PENDING", "EXPECTED":
			pending = true
		}
		if check.Status != "" && !strings.EqualFold(check.Status, "COMPLETED") {
			pending = true
		}
	}
	if pending {
		return "pending"
	}
	return "passing"
}

// pullRequestsByBranch picks one pull request per branch: an open one if
// there is one, else a merged one, else the latest closed one.
func pullRequestsByBranch(output []byte) (map[string]PullRequestRef, error) {
	var list []ghPullRequest
	if err := json.Unmarshal(output, &list); err != nil {
		return nil, err
	}
	rank := map[string]int{"open": 3, "draft": 3, "merged": 2, "closed": 1}
	byBranch := make(map[string]PullRequestRef, len(list))
	for _, pr := range list {
		state := strings.ToLower(pr.State)
		if state == "open" && pr.IsDraft {
			state = "draft"
		}
		if rank[state] == 0 || pr.HeadRefName == "" {
			continue
		}
		ref := PullRequestRef{Number: pr.Number, State: state, URL: pr.URL, Head: pr.HeadRefOid}
		if have, ok := byBranch[pr.HeadRefName]; ok {
			if rank[have.State] > rank[state] || (rank[have.State] == rank[state] && have.Number > pr.Number) {
				continue
			}
		}
		byBranch[pr.HeadRefName] = ref
	}
	return byBranch, nil
}

func lookPathIn(name, path string) string {
	for _, dir := range filepath.SplitList(path) {
		if dir == "" {
			continue
		}
		candidate := filepath.Join(dir, name)
		if info, err := os.Stat(candidate); err == nil && !info.IsDir() && info.Mode()&0o111 != 0 {
			return candidate
		}
	}
	return ""
}
