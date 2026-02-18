package cli

import (
	"bufio"
	"bytes"
	"errors"
	"fmt"
	"io/fs"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strconv"
	"strings"

	"github.com/sourabhrathourr/hun/internal/client"
	"github.com/sourabhrathourr/hun/internal/config"
	"github.com/sourabhrathourr/hun/internal/daemon"
	"github.com/spf13/cobra"
)

var errOnboardingCanceled = errors.New("onboarding canceled")

const maxSuggestedProjects = 10
const maxFuzzyCandidates = 400

type onboardingOptions struct {
	PathArg string
	NoTUI   bool
}

type onboardingResult struct {
	Completed   bool
	LaunchedTUI bool
	ProjectName string
}

func init() {
	onboardCmd.Flags().Bool("no-tui", false, "Complete onboarding without opening the TUI")
	rootCmd.AddCommand(onboardCmd)
}

var onboardCmd = &cobra.Command{
	Use:   "onboard [path]",
	Short: "Run first-time project onboarding",
	Args:  cobra.MaximumNArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		pathArg := ""
		if len(args) == 1 {
			pathArg = args[0]
		}
		noTUI, _ := cmd.Flags().GetBool("no-tui")
		_, err := runOnboardingFlow(onboardingOptions{
			PathArg: pathArg,
			NoTUI:   noTUI,
		})
		if errors.Is(err, errOnboardingCanceled) {
			fmt.Println("Onboarding canceled.")
			return nil
		}
		return err
	},
}

func runOnboardingFlow(opts onboardingOptions) (onboardingResult, error) {
	var result onboardingResult
	interactive := isInteractiveTerminal()

	printOnboardingIntro()
	dir, err := selectOnboardingDir(opts.PathArg, interactive)
	if err != nil {
		return result, err
	}

	for {
		projectName, setupErr := onboardProjectDir(dir)
		if setupErr == nil {
			result.Completed = true
			result.ProjectName = projectName
			break
		}
		if errors.Is(setupErr, errOnboardingCanceled) {
			return result, setupErr
		}
		if interactive && isProjectConflictError(setupErr) {
			fmt.Fprintf(os.Stderr, "Onboarding error: %v\n", setupErr)
			retry, confirmErr := confirmPromptWithDefault("Choose another path? [Y/n] ", true)
			if confirmErr != nil {
				return result, confirmErr
			}
			if !retry {
				return result, setupErr
			}
			nextDir, pickErr := selectOnboardingDir("", interactive)
			if pickErr != nil {
				return result, pickErr
			}
			dir = nextDir
			continue
		}
		return result, setupErr
	}

	if interactive {
		startNow, confirmErr := confirmPrompt(fmt.Sprintf("Start %s now in Focus mode? [Y/n] ", result.ProjectName))
		if confirmErr != nil {
			return result, confirmErr
		}
		if startNow {
			if startErr := startProjectInFocus(result.ProjectName); startErr != nil {
				fmt.Fprintf(os.Stderr, "Warning: could not start %s: %v\n", result.ProjectName, startErr)
			}
		}
	}

	if opts.NoTUI {
		fmt.Println("TUI is your default home: hun")
		return result, nil
	}

	openTUI := interactive
	if interactive {
		choice, confirmErr := confirmPrompt("Open TUI now? [Y/n] ")
		if confirmErr != nil {
			return result, confirmErr
		}
		openTUI = choice
	}
	if !openTUI {
		fmt.Println("TUI is your default home: hun")
		return result, nil
	}

	fmt.Println("TUI is your default home: hun")
	fmt.Println("Keys: p picker   r restart   q quit")
	if err := launchTUI(false); err != nil {
		return result, err
	}
	result.LaunchedTUI = true
	return result, nil
}

func onboardProjectDir(dir string) (string, error) {
	if config.ProjectExists(dir) {
		proj, err := config.LoadProject(dir)
		if err != nil {
			return "", err
		}
		if err := registerProject(proj.Name, dir); err != nil {
			return "", err
		}
		fmt.Printf("%s Ready: %s\n", checkmark(), proj.Name)
		return proj.Name, nil
	}

	name := filepath.Base(dir)
	proj, aborted, err := prepareProjectFromDetection(name, dir, "", false)
	if err != nil {
		return "", err
	}
	if aborted {
		return "", errOnboardingCanceled
	}
	if err := config.WriteProject(dir, proj); err != nil {
		return "", err
	}
	fmt.Printf("%s Created .hun.yml\n", checkmark())
	if err := registerProject(proj.Name, dir); err != nil {
		return "", err
	}
	return proj.Name, nil
}

func startProjectInFocus(project string) error {
	c, err := client.New()
	if err != nil {
		return err
	}
	resp, err := c.Send(daemon.Request{
		Action:  "start",
		Project: project,
		Mode:    "exclusive",
	})
	if err != nil {
		return err
	}
	if !resp.OK {
		return fmt.Errorf("%s", resp.Error)
	}
	return nil
}

func shouldPromptAutoOnboard(interactive bool, registryCount int) bool {
	return interactive && registryCount == 0
}

func selectOnboardingDir(pathArg string, interactive bool) (string, error) {
	if strings.TrimSpace(pathArg) != "" {
		return resolveOnboardingPath(pathArg)
	}

	cwd, err := os.Getwd()
	if err != nil {
		return "", err
	}
	if !interactive {
		return resolveOnboardingPath(cwd)
	}

	reader := bufio.NewReader(os.Stdin)
	useFZF := hasFZF()
	for {
		fmt.Println()
		fmt.Println("Select project directory:")
		fmt.Printf("  1) Use current directory (%s)\n", cwd)
		if useFZF {
			fmt.Println("  2) Search project folders with fzf")
		} else {
			fmt.Println("  2) Pick from recommended projects (top 10)")
		}
		fmt.Println("  3) Enter a path")
		fmt.Println("  4) Cancel")
		fmt.Print("Choice [1/2/3/4]: ")

		choice, readErr := reader.ReadString('\n')
		if readErr != nil && !strings.Contains(readErr.Error(), "EOF") {
			return "", readErr
		}
		switch strings.ToLower(strings.TrimSpace(choice)) {
		case "", "1":
			return resolveOnboardingPath(cwd)
		case "2":
			if useFZF {
				dir, pickErr := pickDirectoryWithFZF(cwd)
				if pickErr != nil {
					return "", pickErr
				}
				if dir == "" {
					continue
				}
				return dir, nil
			}

			suggestions := discoverPathSuggestions(cwd)
			dir, pickErr := pickSuggestedDir(reader, suggestions)
			if pickErr != nil {
				return "", pickErr
			}
			if dir == "" {
				continue
			}
			return dir, nil
		case "3":
			suggestions := []string(nil)
			if !useFZF {
				suggestions = discoverPathSuggestions(cwd)
				if len(suggestions) > 0 {
					fmt.Println("Suggested folders:")
					for i, p := range suggestions {
						fmt.Printf("  %d) %s\n", i+1, shortenPath(p))
					}
				}
				fmt.Print("Path (or suggestion #, empty = current): ")
			} else {
				fmt.Print("Path (empty = current): ")
			}
			pathInput, pathErr := reader.ReadString('\n')
			if pathErr != nil && !strings.Contains(pathErr.Error(), "EOF") {
				return "", pathErr
			}
			trimmed := strings.TrimSpace(pathInput)
			if trimmed == "" {
				return resolveOnboardingPath(cwd)
			}
			if idx, ok := parseSelectionIndex(trimmed, len(suggestions)); ok {
				return suggestions[idx], nil
			}
			dir, resolveErr := resolveOnboardingPath(trimmed)
			if resolveErr != nil {
				fmt.Fprintf(os.Stderr, "Invalid path: %v\n", resolveErr)
				continue
			}
			return dir, nil
		case "4", "q", "quit":
			return "", errOnboardingCanceled
		default:
			fmt.Println("Enter 1, 2, 3, or 4.")
		}
	}
}

func resolveOnboardingPath(raw string) (string, error) {
	path := strings.TrimSpace(raw)
	if path == "" {
		return "", fmt.Errorf("path is required")
	}
	if path == "~" {
		home, err := os.UserHomeDir()
		if err != nil {
			return "", err
		}
		path = home
	} else if strings.HasPrefix(path, "~/") {
		home, err := os.UserHomeDir()
		if err != nil {
			return "", err
		}
		path = filepath.Join(home, strings.TrimPrefix(path, "~/"))
	}

	abs, err := filepath.Abs(path)
	if err != nil {
		return "", err
	}
	info, err := os.Stat(abs)
	if err != nil {
		return "", err
	}
	if !info.IsDir() {
		return "", fmt.Errorf("%s is not a directory", abs)
	}
	return abs, nil
}

func isProjectConflictError(err error) bool {
	if err == nil {
		return false
	}
	msg := err.Error()
	return strings.Contains(msg, "already registered at") || strings.Contains(msg, "already taken")
}

func pickSuggestedDir(reader *bufio.Reader, suggestions []string) (string, error) {
	for {
		if len(suggestions) == 0 {
			fmt.Println("No suggested project folders found.")
			return "", nil
		}

		fmt.Printf("Recommended projects (top %d):\n", len(suggestions))
		for i, p := range suggestions {
			fmt.Printf("  %d) %s\n", i+1, shortenPath(p))
		}
		fmt.Printf("Select [1-%d], m for manual path, or b to go back: ", len(suggestions))

		choice, err := reader.ReadString('\n')
		if err != nil && !strings.Contains(err.Error(), "EOF") {
			return "", err
		}
		trimmed := strings.ToLower(strings.TrimSpace(choice))
		if trimmed == "b" || trimmed == "back" || trimmed == "" {
			return "", nil
		}
		if trimmed == "m" || trimmed == "manual" {
			fmt.Print("Path: ")
			pathInput, pathErr := reader.ReadString('\n')
			if pathErr != nil && !strings.Contains(pathErr.Error(), "EOF") {
				return "", pathErr
			}
			dir, resolveErr := resolveOnboardingPath(pathInput)
			if resolveErr != nil {
				fmt.Fprintf(os.Stderr, "Invalid path: %v\n", resolveErr)
				continue
			}
			return dir, nil
		}
		if idx, ok := parseSelectionIndex(trimmed, len(suggestions)); ok {
			return suggestions[idx], nil
		}
		fmt.Println("Invalid selection.")
	}
}

type projectSuggestion struct {
	path  string
	score int
}

func discoverPathSuggestions(cwd string) []string {
	return discoverPathSuggestionsWithLimit(cwd, maxSuggestedProjects)
}

func discoverPathSuggestionsWithLimit(cwd string, limit int) []string {
	seen := make(map[string]struct{})
	all := make([]string, 0, 64)

	add := func(path string) {
		abs, err := filepath.Abs(path)
		if err != nil {
			return
		}
		if _, ok := seen[abs]; ok {
			return
		}
		if !looksLikeProjectDir(abs) {
			return
		}
		seen[abs] = struct{}{}
		all = append(all, abs)
	}

	scanChildren := func(root string) {
		entries, err := os.ReadDir(root)
		if err != nil {
			return
		}
		for _, e := range entries {
			if !e.IsDir() || strings.HasPrefix(e.Name(), ".") {
				continue
			}
			add(filepath.Join(root, e.Name()))
		}
	}

	add(cwd)
	scanChildren(cwd)
	if parent := filepath.Dir(cwd); parent != cwd {
		scanChildren(parent)
		if grandparent := filepath.Dir(parent); grandparent != parent && grandparent != string(os.PathSeparator) {
			scanChildren(grandparent)
		}
	}

	if home, err := os.UserHomeDir(); err == nil {
		for _, dirName := range []string{"code", "projects", "side-projects", "work", "dev"} {
			scanChildren(filepath.Join(home, dirName))
		}
	}

	ranked := make([]projectSuggestion, 0, len(all))
	for _, p := range all {
		ranked = append(ranked, projectSuggestion{
			path:  p,
			score: projectRelevanceScore(p, cwd),
		})
	}
	sort.Slice(ranked, func(i, j int) bool {
		if ranked[i].score != ranked[j].score {
			return ranked[i].score > ranked[j].score
		}
		return ranked[i].path < ranked[j].path
	})

	selected := len(ranked)
	if limit > 0 && selected > limit {
		selected = limit
	}
	out := make([]string, 0, selected)
	for i := 0; i < selected; i++ {
		out = append(out, ranked[i].path)
	}
	return out
}

func projectRelevanceScore(path, cwd string) int {
	score := 0
	if path == cwd {
		score += 1000
	}

	score += proximityScore(path, cwd)

	if config.ProjectExists(path) {
		score += 300
	}
	if hasFile(path, ".git") {
		score += 120
	}
	for _, marker := range []string{
		"package.json",
		"go.mod",
		"pyproject.toml",
		"requirements.txt",
		"manage.py",
		"docker-compose.yml",
		"compose.yml",
	} {
		if hasFile(path, marker) {
			score += 40
		}
	}
	return score
}

func proximityScore(path, cwd string) int {
	cleanPath := filepath.Clean(path)
	cleanCwd := filepath.Clean(cwd)
	if cleanPath == cleanCwd {
		return 0
	}

	score := 0
	sep := string(os.PathSeparator)

	// Prefer nested projects when user is already inside a monorepo root.
	if strings.HasPrefix(cleanPath, cleanCwd+sep) {
		score += 180
	}

	// Prefer siblings under the same parent directory.
	if filepath.Dir(cleanPath) == filepath.Dir(cleanCwd) {
		score += 220
	}

	// Prefer "one level up" siblings (children of cwd's grandparent).
	parent := filepath.Dir(cleanCwd)
	grandparent := filepath.Dir(parent)
	if grandparent != parent && filepath.Dir(cleanPath) == grandparent {
		score += 120
	}

	return score
}

func hasFile(dir, name string) bool {
	_, err := os.Stat(filepath.Join(dir, name))
	return err == nil
}

func parseSelectionIndex(raw string, size int) (int, bool) {
	if size <= 0 {
		return 0, false
	}
	n, err := strconv.Atoi(strings.TrimSpace(raw))
	if err != nil || n < 1 || n > size {
		return 0, false
	}
	return n - 1, true
}

func looksLikeProjectDir(dir string) bool {
	info, err := os.Stat(dir)
	if err != nil || !info.IsDir() {
		return false
	}
	if config.ProjectExists(dir) {
		return true
	}
	if hasFile(dir, ".git") {
		return true
	}

	markers := []string{
		"package.json",
		"go.mod",
		"pyproject.toml",
		"requirements.txt",
		"manage.py",
		"docker-compose.yml",
		"compose.yml",
	}
	for _, marker := range markers {
		if hasFile(dir, marker) {
			return true
		}
	}
	return false
}

func shortenPath(path string) string {
	home, err := os.UserHomeDir()
	if err != nil || home == "" {
		return path
	}
	if path == home {
		return "~"
	}
	prefix := home + string(os.PathSeparator)
	if strings.HasPrefix(path, prefix) {
		return "~" + string(os.PathSeparator) + strings.TrimPrefix(path, prefix)
	}
	return path
}

func hasFZF() bool {
	_, err := exec.LookPath("fzf")
	return err == nil
}

func pickDirectoryWithFZF(cwd string) (string, error) {
	candidates := discoverFZFProjectCandidates(cwd)
	if len(candidates) == 0 {
		fmt.Println("No project-like directories found. Use option 3 to enter a path.")
		return "", nil
	}

	cmd := exec.Command("fzf", "--prompt", "hun project> ", "--height", "45%", "--reverse")
	cmd.Stdin = strings.NewReader(strings.Join(candidates, "\n") + "\n")
	var out bytes.Buffer
	cmd.Stdout = &out
	cmd.Stderr = os.Stderr
	if err := cmd.Run(); err != nil {
		var exitErr *exec.ExitError
		if errors.As(err, &exitErr) {
			// fzf returns non-zero when user aborts; treat as no selection.
			return "", nil
		}
		return "", err
	}

	selected := strings.TrimSpace(out.String())
	if selected == "" {
		return "", nil
	}
	return selected, nil
}

type scanRoot struct {
	path  string
	depth int
}

func discoverFZFProjectCandidates(cwd string) []string {
	seen := make(map[string]struct{})
	all := make([]string, 0, 256)

	add := func(path string) {
		abs, err := filepath.Abs(path)
		if err != nil {
			return
		}
		if _, ok := seen[abs]; ok {
			return
		}
		if !looksLikeProjectDir(abs) {
			return
		}
		seen[abs] = struct{}{}
		all = append(all, abs)
	}

	for _, root := range scanRootsForFZF(cwd) {
		walkProjectDirs(root.path, root.depth, add)
		if len(all) >= maxFuzzyCandidates*3 {
			break
		}
	}

	ranked := make([]projectSuggestion, 0, len(all))
	for _, p := range all {
		ranked = append(ranked, projectSuggestion{
			path:  p,
			score: projectRelevanceScore(p, cwd),
		})
	}
	sort.Slice(ranked, func(i, j int) bool {
		if ranked[i].score != ranked[j].score {
			return ranked[i].score > ranked[j].score
		}
		return ranked[i].path < ranked[j].path
	})

	limit := len(ranked)
	if limit > maxFuzzyCandidates {
		limit = maxFuzzyCandidates
	}
	out := make([]string, 0, limit)
	for i := 0; i < limit; i++ {
		out = append(out, ranked[i].path)
	}
	return out
}

func scanRootsForFZF(cwd string) []scanRoot {
	roots := make([]scanRoot, 0, 8)
	appendIfDir := func(path string, depth int) {
		if path == "" || depth <= 0 {
			return
		}
		info, err := os.Stat(path)
		if err != nil || !info.IsDir() {
			return
		}
		roots = append(roots, scanRoot{path: filepath.Clean(path), depth: depth})
	}

	appendIfDir(cwd, 4)
	if parent := filepath.Dir(cwd); parent != cwd {
		appendIfDir(parent, 3)
		if grandparent := filepath.Dir(parent); grandparent != parent && grandparent != string(os.PathSeparator) {
			appendIfDir(grandparent, 2)
		}
	}
	if home, err := os.UserHomeDir(); err == nil {
		for _, dirName := range []string{"code", "projects", "side-projects", "work", "dev"} {
			appendIfDir(filepath.Join(home, dirName), 4)
		}
	}

	seen := make(map[string]struct{})
	out := make([]scanRoot, 0, len(roots))
	for _, r := range roots {
		if _, ok := seen[r.path]; ok {
			continue
		}
		seen[r.path] = struct{}{}
		out = append(out, r)
	}
	return out
}

func walkProjectDirs(root string, maxDepth int, add func(string)) {
	absRoot := filepath.Clean(root)
	_ = filepath.WalkDir(absRoot, func(path string, d fs.DirEntry, err error) error {
		if err != nil {
			if d != nil && d.IsDir() {
				return filepath.SkipDir
			}
			return nil
		}
		if !d.IsDir() {
			return nil
		}

		if path != absRoot {
			name := d.Name()
			if shouldPruneWalkDir(name) {
				return filepath.SkipDir
			}
		}
		if dirDepthFromRoot(absRoot, path) > maxDepth {
			return filepath.SkipDir
		}
		if path != absRoot && looksLikeProjectDir(path) {
			add(path)
		}
		return nil
	})
}

func shouldPruneWalkDir(name string) bool {
	if name == "" {
		return false
	}
	if strings.HasPrefix(name, ".") {
		return true
	}
	switch name {
	case "node_modules", "vendor", ".cache", "dist", "build", ".next", "target", "tmp":
		return true
	default:
		return false
	}
}

func dirDepthFromRoot(root, path string) int {
	rel, err := filepath.Rel(root, path)
	if err != nil || rel == "." {
		return 0
	}
	return strings.Count(rel, string(os.PathSeparator)) + 1
}

func printOnboardingIntro() {
	fmt.Println()
	fmt.Println(" _                     ")
	fmt.Println("| |__  _   _ _ __      ")
	fmt.Println("| '_ \\| | | | '_ \\ ")
	fmt.Println("| | | | |_| | | | |    ")
	fmt.Println("|_| |_|\\__,_|_| |_|")
	fmt.Println()
	fmt.Println("Welcome to hun.")
	fmt.Println("TUI-first project onboarding in one flow.")
	fmt.Println()
}
