package daemon

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/sourabhrathourr/hun/internal/discovery"
)

// A worktree on its main checkout's .hun.yml must keep the name registering
// it returns, or `hun add` prints a name `hun run` then can't find.
func TestRegisteringAWorktreeReturnsTheNameDiscoveryKeeps(t *testing.T) {
	m, main, worktree := newWorktreeFixture(t, "feat-r")
	m.st.ForgetProject("repo-wt")
	if err := os.WriteFile(filepath.Join(main, ".hun.yml"), []byte("name: shop\nservices:\n  web:\n    cmd: sleep 1\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	if _, _, _, err := m.RegisterProjectPath(main); err != nil {
		t.Fatal(err)
	}

	_, key, _, err := m.RegisterProjectPath(worktree)
	if err != nil {
		t.Fatal(err)
	}
	if key != "shop-wt" {
		t.Fatalf("registered as %q, want shop-wt", key)
	}
	discovery.Reconcile(m.st, discovery.Result{}, func(string) bool { return false })
	if path, ok := m.st.Registry[key]; !ok || path != filepath.Clean(worktree) {
		t.Fatalf("a scan moved %s: registry %v", key, m.st.Registry)
	}
}
