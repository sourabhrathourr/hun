package daemon

import (
	"bytes"
	"context"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"time"
)

const maximumGitDiffBytes = 32 * 1024 * 1024
const gitCommandTimeout = 2 * time.Minute

// GitStatus is a stable, UI-oriented snapshot of a registered project's
// repository. Git remains the source of truth; Hun does not maintain its own
// index or branch state.
type GitStatus struct {
	IsRepository bool            `json:"is_repository"`
	Branch       string          `json:"branch,omitempty"`
	Head         string          `json:"head,omitempty"`
	Upstream     string          `json:"upstream,omitempty"`
	Ahead        int             `json:"ahead"`
	Behind       int             `json:"behind"`
	Detached     bool            `json:"detached"`
	Clean        bool            `json:"clean"`
	Operation    string          `json:"operation,omitempty"`
	Files        []GitFileChange `json:"files"`
}

// GitFileChange preserves Git's two-column status so the UI can show the same
// path in both staged and unstaged groups when appropriate.
type GitFileChange struct {
	Path           string `json:"path"`
	OriginalPath   string `json:"original_path,omitempty"`
	IndexStatus    string `json:"index_status"`
	WorktreeStatus string `json:"worktree_status"`
	Untracked      bool   `json:"untracked"`
	Conflicted     bool   `json:"conflicted"`
}

type GitBranch struct {
	Name      string `json:"name"`
	Current   bool   `json:"current"`
	Remote    bool   `json:"remote"`
	Upstream  string `json:"upstream,omitempty"`
	UpdatedAt int64  `json:"updated_at"`
}

type GitDiff struct {
	Path      string `json:"path"`
	Staged    bool   `json:"staged"`
	Content   string `json:"content"`
	Binary    bool   `json:"binary"`
	Truncated bool   `json:"truncated"`
}

type GitUpdateResult struct {
	Status           GitStatus `json:"status"`
	UpdatedCommits   int       `json:"updated_commits"`
	ProtectedChanges bool      `json:"protected_changes"`
	RestoredChanges  bool      `json:"restored_changes"`
	RecoveryRequired bool      `json:"recovery_required"`
	RecoveryMessage  string    `json:"recovery_message,omitempty"`
}

func (d *Daemon) handleGitStatus(req Request) Response {
	path, response := d.gitProjectPath(req)
	if !response.OK {
		return response
	}

	status, err := readGitStatus(path)
	if err != nil {
		return errorResponse(err.Error())
	}
	return successResponse(status)
}

func (d *Daemon) handleGitBranches(req Request) Response {
	path, response := d.gitProjectPath(req)
	if !response.OK {
		return response
	}
	branches, err := readGitBranches(path)
	if err != nil {
		return errorResponse(err.Error())
	}
	return successResponse(branches)
}

func (d *Daemon) handleGitDiff(req Request) Response {
	path, response := d.gitProjectPath(req)
	if !response.OK {
		return response
	}
	relativePath, err := safeGitPath(req.Path)
	if err != nil {
		return errorResponse(err.Error())
	}
	diff, err := readGitDiff(path, relativePath, req.Staged)
	if err != nil {
		return errorResponse(err.Error())
	}
	return successResponse(diff)
}

func (d *Daemon) handleGitStage(req Request) Response {
	return d.handleGitPathMutation(req, func(repository, path string) error {
		_, err := runGit(repository, "add", "--", literalGitPath(path))
		return err
	})
}

func (d *Daemon) handleGitStageAll(req Request) Response {
	repository, response := d.gitProjectPath(req)
	if !response.OK {
		return response
	}
	status, err := readGitStatus(repository)
	if err != nil {
		return errorResponse(err.Error())
	}
	for _, change := range status.Files {
		if change.Conflicted {
			return errorResponse("resolve conflicts before staging all changes")
		}
	}
	if _, err := runGit(repository, "add", "-A"); err != nil {
		return errorResponse(err.Error())
	}
	return d.gitStatusResponse(repository)
}

func (d *Daemon) handleGitUnstage(req Request) Response {
	return d.handleGitPathMutation(req, func(repository, path string) error {
		if _, err := runGit(repository, "rev-parse", "--verify", "HEAD"); err != nil {
			_, err = runGit(repository, "rm", "--cached", "--ignore-unmatch", "--", literalGitPath(path))
			return err
		}
		_, err := runGit(repository, "restore", "--staged", "--", literalGitPath(path))
		return err
	})
}

func (d *Daemon) handleGitPathMutation(
	req Request,
	mutate func(repository, path string) error,
) Response {
	repository, response := d.gitProjectPath(req)
	if !response.OK {
		return response
	}
	path, err := safeGitPath(req.Path)
	if err != nil {
		return errorResponse(err.Error())
	}
	if err := mutate(repository, path); err != nil {
		return errorResponse(err.Error())
	}
	return d.gitStatusResponse(repository)
}

func (d *Daemon) handleGitCommit(req Request) Response {
	repository, response := d.gitProjectPath(req)
	if !response.OK {
		return response
	}
	message := strings.TrimSpace(req.Message)
	if message == "" {
		return errorResponse("commit message required")
	}
	if _, err := runGit(repository, "commit", "-m", message); err != nil {
		return errorResponse(err.Error())
	}
	return d.gitStatusResponse(repository)
}

func (d *Daemon) handleGitCreateBranch(req Request) Response {
	repository, response := d.gitProjectPath(req)
	if !response.OK {
		return response
	}
	branch, err := validatedBranchName(repository, req.Branch)
	if err != nil {
		return errorResponse(err.Error())
	}
	if _, err := runGit(repository, "switch", "-c", branch); err != nil {
		return errorResponse(err.Error())
	}
	return d.gitStatusResponse(repository)
}

func (d *Daemon) handleGitSwitchBranch(req Request) Response {
	repository, response := d.gitProjectPath(req)
	if !response.OK {
		return response
	}
	branch, err := validatedBranchName(repository, req.Branch)
	if err != nil {
		return errorResponse(err.Error())
	}
	stashed := false
	if req.Stash {
		if _, err := runGit(
			repository,
			"stash", "push", "--include-untracked", "-m", "Hun: switch from "+currentGitBranch(repository),
		); err != nil {
			return errorResponse(err.Error())
		}
		stashed = true
	}
	if err := switchGitBranch(repository, branch); err != nil {
		if stashed {
			return errorResponse(err.Error() + "; local changes were safely left in the latest stash")
		}
		return errorResponse(err.Error())
	}
	return d.gitStatusResponse(repository)
}

func (d *Daemon) handleGitFetch(req Request) Response {
	repository, response := d.gitProjectPath(req)
	if !response.OK {
		return response
	}
	if _, err := runGit(repository, "fetch", "--prune"); err != nil {
		return errorResponse(err.Error())
	}
	return d.gitStatusResponse(repository)
}

func (d *Daemon) handleGitPull(req Request) Response {
	repository, response := d.gitProjectPath(req)
	if !response.OK {
		return response
	}
	if _, err := runGit(repository, "pull", "--ff-only"); err != nil {
		return errorResponse(err.Error())
	}
	return d.gitStatusResponse(repository)
}

func (d *Daemon) handleGitUpdateBranch(req Request) Response {
	repository, response := d.gitProjectPath(req)
	if !response.OK {
		return response
	}
	if _, err := runGit(repository, "fetch", "--prune"); err != nil {
		return errorResponse(err.Error())
	}

	status, err := readGitStatus(repository)
	if err != nil {
		return errorResponse(err.Error())
	}
	if status.Detached || status.Branch == "" {
		return errorResponse("check out a branch before updating")
	}
	if status.Upstream == "" {
		return errorResponse("current branch has no upstream remote branch")
	}
	if status.Operation != "" || gitStatusHasConflicts(status) {
		return errorResponse("resolve the current Git operation and conflicts before updating")
	}
	if status.Ahead > 0 && status.Behind > 0 {
		return errorResponse("local and remote both changed; rebase or merge before updating")
	}
	if status.Behind == 0 {
		return successResponse(GitUpdateResult{Status: status})
	}

	updatedCommits := status.Behind
	safetyStash := ""
	if !status.Clean {
		if !req.Stash {
			return errorResponse("local changes must be protected before updating")
		}
		safetyStash, err = createGitSafetyStash(repository, "Hun: update "+status.Branch)
		if err != nil {
			return errorResponse("could not protect local changes: " + err.Error())
		}
	}

	if _, err := runGit(repository, "merge", "--ff-only", status.Upstream); err != nil {
		if safetyStash != "" {
			restored, stashKept, restoreErr := restoreGitSafetyStash(repository, safetyStash)
			if restoreErr != nil {
				recovery := "local changes remain in the Hun safety stash"
				if restored {
					recovery = "local changes were restored, but the Hun safety stash was kept"
				} else if !stashKept {
					recovery = "local changes could not be restored"
				}
				return errorResponse(
					"branch update stopped; " + recovery + ": " + restoreErr.Error(),
				)
			}
		}
		return errorResponse("branch could not be fast-forwarded: " + err.Error())
	}

	restoredChanges := false
	recoveryRequired := false
	recoveryMessage := ""
	if safetyStash != "" {
		var stashKept bool
		var restoreErr error
		restoredChanges, stashKept, restoreErr = restoreGitSafetyStash(repository, safetyStash)
		if restoreErr != nil {
			recoveryRequired = true
			if restoredChanges && stashKept {
				recoveryMessage = "Local changes were restored, but the Hun safety stash was kept and can be removed after review."
			} else {
				recoveryMessage = "Remote commits were applied, but local changes need attention. The Hun safety stash was kept."
			}
		}
	}

	updatedStatus, err := readGitStatus(repository)
	if err != nil {
		return errorResponse(err.Error())
	}
	return successResponse(GitUpdateResult{
		Status:           updatedStatus,
		UpdatedCommits:   updatedCommits,
		ProtectedChanges: safetyStash != "",
		RestoredChanges:  restoredChanges,
		RecoveryRequired: recoveryRequired,
		RecoveryMessage:  recoveryMessage,
	})
}

func createGitSafetyStash(repository, message string) (string, error) {
	previousStash := currentGitStashOID(repository)
	if _, err := runGit(
		repository,
		"stash", "push", "--include-untracked", "-m", message,
	); err != nil {
		return "", err
	}
	createdStash := currentGitStashOID(repository)
	if createdStash == "" || createdStash == previousStash {
		return "", fmt.Errorf("Git did not create a safety stash for every local change")
	}
	return createdStash, nil
}

func restoreGitSafetyStash(repository, stashOID string) (restored, stashKept bool, err error) {
	if _, err := runGit(repository, "stash", "apply", "--index", stashOID); err != nil {
		return false, true, err
	}
	if err := dropGitSafetyStash(repository, stashOID); err != nil {
		return true, true, err
	}
	return true, false, nil
}

func dropGitSafetyStash(repository, stashOID string) error {
	output, err := runGit(repository, "stash", "list", "--format=%H%x09%gd")
	if err != nil {
		return err
	}
	for _, line := range strings.Split(strings.TrimSpace(string(output)), "\n") {
		fields := strings.SplitN(line, "\t", 2)
		if len(fields) != 2 || fields[0] != stashOID {
			continue
		}
		resolved, err := runGit(repository, "rev-parse", "--verify", fields[1])
		if err != nil || strings.TrimSpace(string(resolved)) != stashOID {
			continue
		}
		if _, err := runGit(repository, "stash", "drop", fields[1]); err != nil {
			return err
		}
		return nil
	}
	return fmt.Errorf("Hun safety stash %s was not found", stashOID)
}

func currentGitStashOID(repository string) string {
	output, err := runGit(repository, "rev-parse", "--verify", "refs/stash")
	if err != nil {
		return ""
	}
	return strings.TrimSpace(string(output))
}

func gitStatusHasConflicts(status GitStatus) bool {
	for _, file := range status.Files {
		if file.Conflicted {
			return true
		}
	}
	return false
}

func (d *Daemon) handleGitPush(req Request) Response {
	repository, response := d.gitProjectPath(req)
	if !response.OK {
		return response
	}
	status, err := readGitStatus(repository)
	if err != nil {
		return errorResponse(err.Error())
	}
	if status.Detached || status.Branch == "" {
		return errorResponse("cannot push from a detached HEAD")
	}

	if status.Upstream == "" {
		if _, err := runGit(repository, "push", "--set-upstream", "origin", status.Branch); err != nil {
			return errorResponse(err.Error())
		}
	} else if _, err := runGit(repository, "push"); err != nil {
		return errorResponse(err.Error())
	}
	return d.gitStatusResponse(repository)
}

func (d *Daemon) gitStatusResponse(repository string) Response {
	status, err := readGitStatus(repository)
	if err != nil {
		return errorResponse(err.Error())
	}
	return successResponse(status)
}

func (d *Daemon) gitProjectPath(req Request) (string, Response) {
	if req.Project == "" {
		return "", errorResponse("project name required")
	}
	path, ok := d.manager.ProjectPath(req.Project)
	if !ok {
		return "", errorResponse(fmt.Sprintf("project %q not in registry", req.Project))
	}
	return path, successResponse(nil)
}

func readGitBranches(repository string) ([]GitBranch, error) {
	output, err := runGit(
		repository,
		"for-each-ref",
		"--format=%(refname)\t%(refname:short)\t%(HEAD)\t%(upstream:short)\t%(committerdate:unix)",
		"refs/heads", "refs/remotes",
	)
	if err != nil {
		return nil, err
	}

	branches := make([]GitBranch, 0)
	for _, line := range strings.Split(strings.TrimSpace(string(output)), "\n") {
		if line == "" {
			continue
		}
		fields := strings.Split(line, "\t")
		if len(fields) != 5 {
			continue
		}
		if strings.HasSuffix(fields[0], "/HEAD") {
			continue
		}
		updatedAt, _ := strconv.ParseInt(fields[4], 10, 64)
		branches = append(branches, GitBranch{
			Name:      fields[1],
			Current:   fields[2] == "*",
			Remote:    strings.HasPrefix(fields[0], "refs/remotes/"),
			Upstream:  fields[3],
			UpdatedAt: updatedAt,
		})
	}
	sort.SliceStable(branches, func(i, j int) bool {
		if branches[i].Current != branches[j].Current {
			return branches[i].Current
		}
		if branches[i].Remote != branches[j].Remote {
			return !branches[i].Remote
		}
		if branches[i].UpdatedAt != branches[j].UpdatedAt {
			return branches[i].UpdatedAt > branches[j].UpdatedAt
		}
		return branches[i].Name < branches[j].Name
	})
	return branches, nil
}

func readGitDiff(repository, path string, staged bool) (GitDiff, error) {
	arguments := []string{
		"-c", "core.quotepath=false",
		"diff", "--no-ext-diff", "--unified=3",
	}
	if staged {
		arguments = append(arguments, "--cached")
	}
	arguments = append(arguments, "--", literalGitPath(path))
	output, truncated, err := runGitWithOutputLimit(
		repository,
		maximumGitDiffBytes,
		nil,
		arguments...,
	)
	if err != nil {
		return GitDiff{}, err
	}

	if len(output) == 0 && !staged && !truncated {
		status, statusErr := readGitStatus(repository)
		if statusErr != nil {
			return GitDiff{}, statusErr
		}
		for _, change := range status.Files {
			if change.Path == path && change.Untracked {
				output, truncated, err = runGitWithOutputLimit(
					repository,
					maximumGitDiffBytes,
					map[int]bool{1: true},
					"-c", "core.quotepath=false",
					"diff", "--no-index", "--no-ext-diff", "--unified=3",
					"--", "/dev/null", path,
				)
				if err != nil {
					return GitDiff{}, err
				}
				break
			}
		}
	}

	content := string(output)
	return GitDiff{
		Path:      path,
		Staged:    staged,
		Content:   content,
		Binary:    strings.Contains(content, "Binary files "),
		Truncated: truncated,
	}, nil
}

type cappedGitOutput struct {
	buffer    bytes.Buffer
	limit     int
	truncated bool
	onLimit   func()
}

func (output *cappedGitOutput) Write(data []byte) (int, error) {
	originalLength := len(data)
	remaining := output.limit - output.buffer.Len()
	if remaining > 0 {
		if len(data) > remaining {
			data = data[:remaining]
		}
		_, _ = output.buffer.Write(data)
	}
	if originalLength > remaining && !output.truncated {
		output.truncated = true
		if output.onLimit != nil {
			output.onLimit()
		}
	}
	return originalLength, nil
}

func safeGitPath(path string) (string, error) {
	if strings.TrimSpace(path) == "" {
		return "", fmt.Errorf("file path required")
	}
	if filepath.IsAbs(path) {
		return "", fmt.Errorf("git file path must be relative")
	}
	clean := filepath.Clean(path)
	if clean == "." || clean == ".." || strings.HasPrefix(clean, ".."+string(filepath.Separator)) {
		return "", fmt.Errorf("git file path must stay inside the project")
	}
	return filepath.ToSlash(clean), nil
}

func literalGitPath(path string) string {
	return ":(literal)" + path
}

func validatedBranchName(repository, branch string) (string, error) {
	branch = strings.TrimSpace(branch)
	if branch == "" {
		return "", fmt.Errorf("branch name required")
	}
	if _, err := runGit(repository, "check-ref-format", "--branch", branch); err != nil {
		return "", fmt.Errorf("invalid branch name %q", branch)
	}
	return branch, nil
}

func switchGitBranch(repository, branch string) error {
	branches, err := readGitBranches(repository)
	if err != nil {
		return err
	}
	for _, candidate := range branches {
		if candidate.Name != branch {
			continue
		}
		if !candidate.Remote {
			_, err = runGit(repository, "switch", branch)
			return err
		}
		parts := strings.SplitN(branch, "/", 2)
		if len(parts) != 2 {
			break
		}
		localName := parts[1]
		for _, local := range branches {
			if !local.Remote && local.Name == localName {
				if local.Upstream == branch {
					_, err = runGit(repository, "switch", localName)
					return err
				}
				tracking := local.Upstream
				if tracking == "" {
					tracking = "no remote branch"
				}
				return fmt.Errorf(
					"cannot switch remote branch %q: local branch %q tracks %q",
					branch,
					localName,
					tracking,
				)
			}
		}
		_, err = runGit(repository, "switch", "--track", "-c", localName, branch)
		return err
	}
	return fmt.Errorf("branch %q not found", branch)
}

func readGitStatus(repository string) (GitStatus, error) {
	status := GitStatus{Files: []GitFileChange{}}
	inside, err := runGit(repository, "rev-parse", "--is-inside-work-tree")
	if err != nil {
		if strings.Contains(err.Error(), "not a git repository") {
			return status, nil
		}
		return status, err
	}
	if strings.TrimSpace(string(inside)) != "true" {
		return status, nil
	}
	status.IsRepository = true

	output, err := runGit(
		repository,
		"-c", "core.quotepath=false",
		"status", "--porcelain=v2", "--branch", "-z",
	)
	if err != nil {
		return GitStatus{}, err
	}
	if err := parseGitStatus(output, &status); err != nil {
		return GitStatus{}, err
	}
	status.Operation = detectGitOperation(repository)
	status.Clean = len(status.Files) == 0
	sort.Slice(status.Files, func(i, j int) bool {
		return status.Files[i].Path < status.Files[j].Path
	})
	return status, nil
}

func parseGitStatus(output []byte, status *GitStatus) error {
	records := bytes.Split(output, []byte{0})
	for index := 0; index < len(records); index++ {
		record := string(records[index])
		if record == "" {
			continue
		}

		if strings.HasPrefix(record, "# ") {
			for _, header := range strings.Split(record, "\n") {
				parseGitStatusHeader(header, status)
			}
			continue
		}

		change, consumesOriginalPath, err := parseGitChange(record)
		if err != nil {
			return err
		}
		if consumesOriginalPath {
			index++
			if index >= len(records) {
				return fmt.Errorf("parsing git status: renamed path is missing its source")
			}
			change.OriginalPath = string(records[index])
		}
		status.Files = append(status.Files, change)
	}
	return nil
}

func parseGitStatusHeader(header string, status *GitStatus) {
	switch {
	case strings.HasPrefix(header, "# branch.oid "):
		status.Head = strings.TrimPrefix(header, "# branch.oid ")
	case strings.HasPrefix(header, "# branch.head "):
		status.Branch = strings.TrimPrefix(header, "# branch.head ")
		status.Detached = status.Branch == "(detached)"
	case strings.HasPrefix(header, "# branch.upstream "):
		status.Upstream = strings.TrimPrefix(header, "# branch.upstream ")
	case strings.HasPrefix(header, "# branch.ab "):
		fields := strings.Fields(strings.TrimPrefix(header, "# branch.ab "))
		for _, field := range fields {
			if strings.HasPrefix(field, "+") {
				status.Ahead, _ = strconv.Atoi(strings.TrimPrefix(field, "+"))
			}
			if strings.HasPrefix(field, "-") {
				status.Behind, _ = strconv.Atoi(strings.TrimPrefix(field, "-"))
			}
		}
	}
}

func parseGitChange(record string) (GitFileChange, bool, error) {
	switch {
	case strings.HasPrefix(record, "1 "):
		fields := strings.SplitN(record, " ", 9)
		if len(fields) != 9 || len(fields[1]) != 2 {
			return GitFileChange{}, false, fmt.Errorf("parsing ordinary git status record")
		}
		return gitFileChange(fields[8], fields[1]), false, nil
	case strings.HasPrefix(record, "2 "):
		fields := strings.SplitN(record, " ", 10)
		if len(fields) != 10 || len(fields[1]) != 2 {
			return GitFileChange{}, false, fmt.Errorf("parsing renamed git status record")
		}
		return gitFileChange(fields[9], fields[1]), true, nil
	case strings.HasPrefix(record, "u "):
		fields := strings.SplitN(record, " ", 11)
		if len(fields) != 11 || len(fields[1]) != 2 {
			return GitFileChange{}, false, fmt.Errorf("parsing conflicted git status record")
		}
		change := gitFileChange(fields[10], fields[1])
		change.Conflicted = true
		return change, false, nil
	case strings.HasPrefix(record, "? "):
		return GitFileChange{
			Path:           strings.TrimPrefix(record, "? "),
			IndexStatus:    "?",
			WorktreeStatus: "?",
			Untracked:      true,
		}, false, nil
	default:
		return GitFileChange{}, false, fmt.Errorf("parsing unsupported git status record %q", record)
	}
}

func gitFileChange(path, status string) GitFileChange {
	indexStatus := status[:1]
	worktreeStatus := status[1:]
	conflicted := false
	switch status {
	case "DD", "AU", "UD", "UA", "DU", "AA", "UU":
		conflicted = true
	}
	return GitFileChange{
		Path:           path,
		IndexStatus:    indexStatus,
		WorktreeStatus: worktreeStatus,
		Conflicted:     conflicted,
	}
}

func detectGitOperation(repository string) string {
	output, err := runGit(repository, "rev-parse", "--git-dir")
	if err != nil {
		return ""
	}
	gitDirectory := strings.TrimSpace(string(output))
	if !filepath.IsAbs(gitDirectory) {
		gitDirectory = filepath.Join(repository, gitDirectory)
	}
	for _, candidate := range []struct {
		name string
		path string
	}{
		{name: "rebase", path: "rebase-merge"},
		{name: "rebase", path: "rebase-apply"},
		{name: "merge", path: "MERGE_HEAD"},
		{name: "cherry-pick", path: "CHERRY_PICK_HEAD"},
		{name: "revert", path: "REVERT_HEAD"},
		{name: "bisect", path: "BISECT_LOG"},
	} {
		if _, err := os.Stat(filepath.Join(gitDirectory, candidate.path)); err == nil {
			return candidate.name
		}
	}
	return ""
}

func runGit(repository string, arguments ...string) ([]byte, error) {
	return runGitWithAllowedExitCodes(repository, nil, arguments...)
}

func runGitWithAllowedExitCodes(
	repository string,
	allowedExitCodes map[int]bool,
	arguments ...string,
) ([]byte, error) {
	command, cancel := gitCommand(repository, arguments...)
	defer cancel()
	output, err := command.CombinedOutput()
	if err == nil {
		return output, nil
	}
	if exitError, ok := err.(*exec.ExitError); ok && allowedExitCodes[exitError.ExitCode()] {
		return output, nil
	}
	message := strings.TrimSpace(string(output))
	if message == "" {
		message = err.Error()
	}
	return nil, fmt.Errorf("git: %s", message)
}

func runGitWithOutputLimit(
	repository string,
	limit int,
	allowedExitCodes map[int]bool,
	arguments ...string,
) ([]byte, bool, error) {
	command, cancel := gitCommand(repository, arguments...)
	defer cancel()

	output := cappedGitOutput{limit: limit, onLimit: cancel}
	stderr := cappedGitOutput{limit: 64 * 1024}
	command.Stdout = &output
	command.Stderr = &stderr
	err := command.Run()

	if output.truncated {
		return output.buffer.Bytes(), true, nil
	}
	if err == nil {
		return output.buffer.Bytes(), false, nil
	}
	if exitError, ok := err.(*exec.ExitError); ok && allowedExitCodes[exitError.ExitCode()] {
		return output.buffer.Bytes(), false, nil
	}
	message := strings.TrimSpace(stderr.buffer.String())
	if message == "" {
		message = strings.TrimSpace(output.buffer.String())
	}
	if message == "" {
		message = err.Error()
	}
	return nil, false, fmt.Errorf("git: %s", message)
}

func gitCommand(repository string, arguments ...string) (*exec.Cmd, context.CancelFunc) {
	ctx, cancel := context.WithTimeout(context.Background(), gitCommandTimeout)
	command := exec.CommandContext(ctx, "git", arguments...)
	command.Dir = repository
	command.Env = append(
		os.Environ(),
		"GIT_PAGER=cat",
		"GIT_TERMINAL_PROMPT=0",
		"LC_ALL=C",
	)
	return command, cancel
}
