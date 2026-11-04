package daemon

import (
	"fmt"

	"github.com/sourabhrathourr/hun/internal/config"
)

// WorktreeDeletion says what deleting a worktree did.
type WorktreeDeletion struct {
	Status string `json:"status"`
	// Branch is the worktree's branch; BranchDeleted is true when its pull
	// request was merged and the branch had nothing more, so it went too.
	Branch        string `json:"branch,omitempty"`
	BranchDeleted bool   `json:"branch_deleted"`
}

func (d *Daemon) handleDeleteWorktree(req Request) Response {
	if req.Project == "" {
		return errorResponse("project name required")
	}
	result, err := d.manager.DeleteWorktree(req.Project, req.Force)
	if err != nil {
		return errorResponse(err.Error())
	}
	return successResponse(result)
}

// DeleteWorktree stops a linked git worktree's services, removes it with
// git, and stops listing it. It refuses a worktree with uncommitted changes
// unless force is set. The local branch is deleted too when its pull request
// is known to be merged and the branch still ends on the merged commit;
// otherwise it's kept.
func (m *Manager) DeleteWorktree(key string, force bool) (WorktreeDeletion, error) {
	path, ok := m.ProjectPath(key)
	if !ok {
		return WorktreeDeletion{}, fmt.Errorf("project %q not found", key)
	}
	main, ok := config.MainCheckout(path)
	if !ok {
		return WorktreeDeletion{}, fmt.Errorf("%s is not a git worktree", key)
	}
	status, err := readGitStatus(path)
	if err != nil {
		return WorktreeDeletion{}, err
	}
	if !status.Clean && !force {
		noun := "changes"
		if len(status.Files) == 1 {
			noun = "change"
		}
		return WorktreeDeletion{}, fmt.Errorf("%s has %d uncommitted %s", key, len(status.Files), noun)
	}

	if m.IsRunning(key) {
		if err := m.stopProject(key, false); err != nil {
			return WorktreeDeletion{}, fmt.Errorf("stopping %s: %w", key, err)
		}
	}

	arguments := []string{"worktree", "remove"}
	if force {
		arguments = append(arguments, "--force")
	}
	if _, err := runGit(main, append(arguments, path)...); err != nil {
		return WorktreeDeletion{}, err
	}

	result := WorktreeDeletion{Status: "worktree_deleted"}
	if !status.Detached {
		result.Branch = status.Branch
	}
	if result.Branch != "" {
		if pr := m.prs.lookup(main, result.Branch); pr != nil && pr.State == "merged" && pr.Head != "" && pr.Head == status.Head {
			// -D: a squash-merged branch never looks merged to git.
			if _, err := runGit(main, "branch", "-D", result.Branch); err == nil {
				result.BranchDeleted = true
			}
		}
	}

	m.stateMu.Lock()
	m.st.ForgetProject(key)
	err = m.st.Save()
	m.stateMu.Unlock()
	return result, err
}
