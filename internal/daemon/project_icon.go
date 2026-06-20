package daemon

import (
	"fmt"
	"io"
	"io/fs"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"

	"github.com/sourabhrathourr/hun/internal/config"
	"github.com/sourabhrathourr/hun/internal/state"
)

const (
	projectIconCacheTTL = 30 * time.Second
	projectIconMaxDepth = 6
)

type projectIconCacheEntry struct {
	path      string
	scannedAt time.Time
}

var projectIconExactCandidates = []string{
	"public/favicon.svg",
	"public/favicon.png",
	"public/favicon.ico",
	"public/apple-touch-icon.png",
	"public/icon.svg",
	"public/icon.png",
	"public/logo.svg",
	"public/logo.png",
	"static/favicon.svg",
	"static/favicon.png",
	"static/favicon.ico",
	"static/logo.svg",
	"static/logo.png",
	"app/favicon.ico",
	"app/icon.svg",
	"app/icon.png",
	"app/apple-icon.png",
	"src/app/favicon.ico",
	"src/app/icon.svg",
	"src/app/icon.png",
	"src/assets/logo.svg",
	"src/assets/logo.png",
	"assets/logo.svg",
	"assets/logo.png",
	"resources/logo.svg",
	"resources/logo.png",
	"favicon.svg",
	"favicon.png",
	"favicon.ico",
	"logo.svg",
	"logo.png",
	"icon.svg",
	"icon.png",
}

var projectIconExtensions = map[string]int{
	".png":  35,
	".icns": 34,
	".ico":  33,
	".svg":  32,
	".webp": 25,
	".jpg":  20,
	".jpeg": 20,
	".gif":  10,
}

var projectIconSkipDirs = map[string]bool{
	".git":         true,
	".hg":          true,
	".svn":         true,
	".next":        true,
	".nuxt":        true,
	".svelte-kit":  true,
	".turbo":       true,
	".venv":        true,
	"build":        true,
	"coverage":     true,
	"dist":         true,
	"library":      true,
	"node_modules": true,
	"target":       true,
	"vendor":       true,
}

func (m *Manager) SetProjectIcon(projectName, sourcePath string) (string, error) {
	projectPath, ok := m.ProjectPath(projectName)
	if !ok {
		return "", fmt.Errorf("project %q not in registry", projectName)
	}

	ext := strings.ToLower(filepath.Ext(sourcePath))
	if _, ok := projectIconExtensions[ext]; !ok {
		return "", fmt.Errorf("unsupported icon file type %q", ext)
	}
	info, err := os.Stat(sourcePath)
	if err != nil {
		return "", fmt.Errorf("reading icon file: %w", err)
	}
	if info.IsDir() {
		return "", fmt.Errorf("icon path must be a file")
	}

	hunDir, err := config.HunDir()
	if err != nil {
		return "", err
	}
	iconDir := filepath.Join(hunDir, "project-icons")
	if err := os.MkdirAll(iconDir, 0o755); err != nil {
		return "", fmt.Errorf("creating icon directory: %w", err)
	}

	destPath := filepath.Join(iconDir, sanitizeProjectIconFilename(projectName)+ext)
	if filepath.Clean(sourcePath) != filepath.Clean(destPath) {
		if err := copyProjectIcon(sourcePath, destPath); err != nil {
			return "", err
		}
	}

	if err := m.mutateState(func(st *state.State) {
		ps := st.Projects[projectName]
		ps.IconPath = destPath
		st.Projects[projectName] = ps
	}); err != nil {
		return "", err
	}

	m.clearProjectIconCache(projectPath)
	return destPath, nil
}

func (m *Manager) ClearProjectIcon(projectName string) error {
	projectPath, ok := m.ProjectPath(projectName)
	if !ok {
		return fmt.Errorf("project %q not in registry", projectName)
	}
	if err := m.mutateState(func(st *state.State) {
		ps := st.Projects[projectName]
		ps.IconPath = ""
		st.Projects[projectName] = ps
	}); err != nil {
		return err
	}
	m.clearProjectIconCache(projectPath)
	return nil
}

func (m *Manager) projectIconPath(projectPath, customPath string) string {
	if customPath != "" && fileExists(customPath) {
		return customPath
	}

	root := filepath.Clean(projectPath)
	now := time.Now()

	m.iconMu.Lock()
	if cached, ok := m.iconCache[root]; ok && now.Sub(cached.scannedAt) < projectIconCacheTTL {
		if cached.path == "" || fileExists(cached.path) {
			m.iconMu.Unlock()
			return cached.path
		}
	}
	m.iconMu.Unlock()

	iconPath := findProjectIcon(root)

	m.iconMu.Lock()
	m.iconCache[root] = projectIconCacheEntry{path: iconPath, scannedAt: now}
	m.iconMu.Unlock()

	return iconPath
}

func (m *Manager) clearProjectIconCache(projectPath string) {
	m.iconMu.Lock()
	delete(m.iconCache, filepath.Clean(projectPath))
	m.iconMu.Unlock()
}

func findProjectIcon(projectPath string) string {
	seen := make(map[string]bool)
	var matches []projectIconMatch
	for _, rel := range projectIconExactCandidates {
		path := filepath.Join(projectPath, filepath.FromSlash(rel))
		if fileExists(path) {
			seen[path] = true
			if score := projectIconScore(rel); score > 0 {
				matches = append(matches, projectIconMatch{path: path, score: score + 25})
			}
		}
	}

	_ = filepath.WalkDir(projectPath, func(path string, entry fs.DirEntry, err error) error {
		if err != nil {
			if entry != nil && entry.IsDir() {
				return filepath.SkipDir
			}
			return nil
		}

		rel, relErr := filepath.Rel(projectPath, path)
		if relErr != nil || rel == "." {
			return nil
		}

		depth := len(strings.Split(rel, string(os.PathSeparator)))
		if entry.IsDir() {
			if shouldSkipProjectIconDir(entry.Name()) || depth > projectIconMaxDepth {
				return filepath.SkipDir
			}
			return nil
		}
		if depth > projectIconMaxDepth {
			return nil
		}
		if seen[path] {
			return nil
		}

		score := projectIconScore(rel)
		if score <= 0 {
			return nil
		}
		matches = append(matches, projectIconMatch{path: path, score: score})
		return nil
	})

	if len(matches) == 0 {
		return ""
	}
	sort.Slice(matches, func(i, j int) bool {
		if matches[i].score == matches[j].score {
			return matches[i].path < matches[j].path
		}
		return matches[i].score > matches[j].score
	})
	return matches[0].path
}

type projectIconMatch struct {
	path  string
	score int
}

func projectIconScore(rel string) int {
	ext := strings.ToLower(filepath.Ext(rel))
	extScore, ok := projectIconExtensions[ext]
	if !ok {
		return 0
	}

	base := strings.TrimSuffix(filepath.Base(rel), filepath.Ext(rel))
	name := normalizeProjectIconName(base)
	score := 0
	switch {
	case strings.Contains(name, "favicon"):
		score = 1000
	case strings.Contains(name, "appletouchicon"), strings.Contains(name, "appleicon"):
		score = 950
	case name == "appicon", name == "icon":
		score = 850
	case strings.Contains(name, "icon"):
		score = 820
	case name == "logo":
		score = 825
	case strings.Contains(name, "logo"):
		score = 780
	case strings.HasPrefix(name, "brand"), strings.HasSuffix(name, "brand"), strings.Contains(name, "mark"):
		score = 600
	default:
		return 0
	}

	for _, part := range strings.Split(filepath.ToSlash(rel), "/") {
		switch strings.ToLower(part) {
		case "public", "static":
			score += 160
		case "app", "src", "assets", "resources":
			score += 80
		case "icons", "logos", "images", "img":
			score += 60
		}
	}

	score += projectIconSizeHintScore(name)
	if strings.Contains(name, "maskable") {
		score -= 25
	}
	depth := len(strings.Split(filepath.ToSlash(rel), "/"))
	score -= depth * 8
	return score + extScore
}

func normalizeProjectIconName(name string) string {
	replacer := strings.NewReplacer("-", "", "_", "", " ", "", ".", "")
	return replacer.Replace(strings.ToLower(name))
}

func shouldSkipProjectIconDir(name string) bool {
	lower := strings.ToLower(name)
	if strings.HasPrefix(lower, ".") {
		return true
	}
	return projectIconSkipDirs[lower]
}

func fileExists(path string) bool {
	info, err := os.Stat(path)
	return err == nil && !info.IsDir()
}

func projectIconSizeHintScore(name string) int {
	switch {
	case strings.Contains(name, "1024"):
		return 650
	case strings.Contains(name, "512"):
		return 600
	case strings.Contains(name, "256"):
		return 520
	case strings.Contains(name, "192"):
		return 480
	case strings.Contains(name, "180"):
		return 420
	case strings.Contains(name, "128"):
		return 300
	default:
		return 0
	}
}

func sanitizeProjectIconFilename(projectName string) string {
	name := strings.ToLower(projectName)
	var b strings.Builder
	for _, r := range name {
		switch {
		case r >= 'a' && r <= 'z':
			b.WriteRune(r)
		case r >= '0' && r <= '9':
			b.WriteRune(r)
		default:
			b.WriteRune('-')
		}
	}
	clean := strings.Trim(b.String(), "-")
	if clean == "" {
		return "project"
	}
	return clean
}

func copyProjectIcon(sourcePath, destPath string) error {
	src, err := os.Open(sourcePath)
	if err != nil {
		return fmt.Errorf("opening icon file: %w", err)
	}
	defer src.Close()

	tmpPath := destPath + ".tmp"
	dst, err := os.OpenFile(tmpPath, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, 0o644)
	if err != nil {
		return fmt.Errorf("creating icon copy: %w", err)
	}
	if _, err := io.Copy(dst, src); err != nil {
		_ = dst.Close()
		_ = os.Remove(tmpPath)
		return fmt.Errorf("copying icon file: %w", err)
	}
	if err := dst.Close(); err != nil {
		_ = os.Remove(tmpPath)
		return fmt.Errorf("closing icon copy: %w", err)
	}
	if err := os.Rename(tmpPath, destPath); err != nil {
		_ = os.Remove(tmpPath)
		return fmt.Errorf("saving icon copy: %w", err)
	}
	return nil
}
