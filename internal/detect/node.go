package detect

import (
	"encoding/json"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
)

// NodeDetector detects Node.js projects via package.json.
type NodeDetector struct{}

type nodePackageJSON struct {
	Name           string            `json:"name"`
	Scripts        map[string]string `json:"scripts"`
	PackageManager string            `json:"packageManager"`
	Workspaces     json.RawMessage   `json:"workspaces"`
}

type nodePackageContext struct {
	RootDir       string
	Dir           string
	RelDir        string
	Pkg           nodePackageJSON
	Runner        string
	HasWorkspaces bool
	IsRoot        bool
}

func (d *NodeDetector) Detect(dir string) []DetectedService {
	rootPkg, ok := loadNodePackage(filepath.Join(dir, "package.json"))
	if !ok {
		return nil
	}

	rootRunner := detectPackageManager(dir, rootPkg.PackageManager, "")
	workspaceDirs := resolveWorkspaceDirs(dir, rootPkg.Workspaces)
	hasWorkspaces := len(workspaceDirs) > 0

	services := make([]DetectedService, 0)
	services = append(services, detectNodePackage(nodePackageContext{
		RootDir:       dir,
		Dir:           dir,
		RelDir:        "",
		Pkg:           rootPkg,
		Runner:        rootRunner,
		HasWorkspaces: hasWorkspaces,
		IsRoot:        true,
	})...)

	for _, wsDir := range workspaceDirs {
		pkg, ok := loadNodePackage(filepath.Join(wsDir, "package.json"))
		if !ok {
			continue
		}
		rel, err := filepath.Rel(dir, wsDir)
		if err != nil {
			rel = filepath.Base(wsDir)
		}
		rel = filepath.ToSlash(rel)
		runner := detectPackageManager(wsDir, pkg.PackageManager, rootRunner)
		services = append(services, detectNodePackage(nodePackageContext{
			RootDir:       dir,
			Dir:           wsDir,
			RelDir:        rel,
			Pkg:           pkg,
			Runner:        runner,
			HasWorkspaces: hasWorkspaces,
			IsRoot:        false,
		})...)
	}

	sort.Slice(services, func(i, j int) bool {
		a := services[i]
		b := services[j]
		if a.LogicalName != b.LogicalName {
			return a.LogicalName < b.LogicalName
		}
		if a.Source != b.Source {
			return a.Source < b.Source
		}
		return a.Cmd < b.Cmd
	})
	return services
}

func loadNodePackage(path string) (nodePackageJSON, bool) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nodePackageJSON{}, false
	}
	var pkg nodePackageJSON
	if err := json.Unmarshal(data, &pkg); err != nil {
		return nodePackageJSON{}, false
	}
	if len(pkg.Scripts) == 0 {
		return pkg, true
	}
	return pkg, true
}

func detectNodePackage(ctx nodePackageContext) []DetectedService {
	if len(ctx.Pkg.Scripts) == 0 {
		return nil
	}

	var out []DetectedService

	if key, script, ok := selectPrimaryScript(ctx.Pkg.Scripts); ok {
		if !(ctx.IsRoot && ctx.HasWorkspaces && isOrchestratorScript(script)) &&
			!(ctx.HasWorkspaces && isLikelyMobilePackage(ctx.Pkg, ctx.Dir, script)) {
			if svc := buildNodeService(ctx, key, script, true); svc.Name != "" {
				out = append(out, svc)
			}
		}
	}

	backgroundKeys := selectBackgroundScripts(ctx.Pkg.Scripts)
	for _, key := range backgroundKeys {
		script := ctx.Pkg.Scripts[key]
		if ctx.IsRoot && ctx.HasWorkspaces && isOrchestratorScript(script) && !isTargetedScript(script) {
			continue
		}
		if svc := buildNodeService(ctx, key, script, false); svc.Name != "" {
			out = append(out, svc)
		}
	}

	return out
}

func selectPrimaryScript(scripts map[string]string) (name, cmd string, ok bool) {
	for _, key := range []string{"dev", "start:dev", "serve", "start"} {
		if v := strings.TrimSpace(scripts[key]); v != "" {
			return key, v, true
		}
	}
	return "", "", false
}

func selectBackgroundScripts(scripts map[string]string) []string {
	keys := make([]string, 0)
	for key, val := range scripts {
		if strings.TrimSpace(val) == "" {
			continue
		}
		if isBackgroundScriptKey(key) {
			keys = append(keys, key)
		}
	}
	sort.Strings(keys)
	return keys
}

func isBackgroundScriptKey(key string) bool {
	lower := strings.ToLower(strings.TrimSpace(key))
	switch lower {
	case "agent", "worker", "beat", "celery:worker", "celery:beat", "start:agent":
		return true
	}
	if strings.HasSuffix(lower, ":worker") || strings.HasSuffix(lower, ":beat") {
		return true
	}
	return false
}

func buildNodeService(ctx nodePackageContext, scriptName, scriptBody string, primary bool) DetectedService {
	logical := inferNodeServiceName(ctx, scriptName, scriptBody, primary)
	if logical == "" {
		return DetectedService{}
	}

	port, portConfidence, portEnv, ready := inferNodePort(scriptName, scriptBody, ctx.Dir, logical)
	if ready == "" {
		ready = guessNodeReady(logical)
	}

	cwd := ""
	if !ctx.IsRoot {
		cwd = "./" + strings.TrimPrefix(filepath.ToSlash(ctx.RelDir), "./")
	}

	confidence := 0.8
	if primary {
		confidence = 0.9
	}
	if ctx.IsRoot {
		confidence -= 0.05
	}
	if isOrchestratorScript(scriptBody) {
		confidence -= 0.05
	}
	if confidence < 0.1 {
		confidence = 0.1
	}

	source := filepath.ToSlash(filepath.Join(ctx.Dir, "package.json"))
	return DetectedService{
		Name:           logical,
		LogicalName:    logical,
		Cmd:            runScriptCommand(ctx.Runner, scriptName),
		Cwd:            cwd,
		Port:           port,
		PortEnv:        portEnv,
		Ready:          ready,
		Runtime:        "node",
		Strategy:       "local",
		Class:          "app",
		Source:         source,
		Confidence:     confidence,
		PortConfidence: portConfidence,
	}
}

func runScriptCommand(runner, script string) string {
	switch runner {
	case "yarn":
		return "yarn " + script
	default:
		return runner + " run " + script
	}
}

func inferNodeServiceName(ctx nodePackageContext, scriptName, scriptBody string, primary bool) string {
	if primary {
		if !ctx.IsRoot {
			base := filepath.Base(ctx.Dir)
			if base == "" || base == "." {
				base = inferServiceName("", ctx.Pkg.Name, ctx.Dir)
			}
			return normalizeServiceName(base)
		}
		return normalizeServiceName(inferServiceName("", ctx.Pkg.Name, ctx.Dir))
	}

	normScript := normalizeServiceName(scriptName)
	if normScript == "" {
		return ""
	}

	if target := inferScriptTarget(scriptBody); target != "" {
		if shouldUseBareBackgroundName(scriptName, target) {
			return normScript
		}
		return normalizeServiceName(target + "-" + normScript)
	}

	if !ctx.IsRoot {
		workspace := normalizeServiceName(filepath.Base(ctx.Dir))
		if shouldUseBareBackgroundName(scriptName, workspace) {
			return normScript
		}
		return normalizeServiceName(workspace + "-" + normScript)
	}

	return normScript
}

func shouldUseBareBackgroundName(scriptName, contextName string) bool {
	lower := strings.ToLower(scriptName)
	if lower != "agent" && lower != "worker" && lower != "beat" && !strings.Contains(lower, "celery") {
		return false
	}
	ctx := strings.ToLower(contextName)
	return ctx == "api" || ctx == "server" || ctx == "backend"
}

func inferScriptTarget(script string) string {
	lower := strings.ToLower(script)
	if strings.Contains(lower, "--filter") {
		if m := regexp.MustCompile(`--filter(?:=|\s+)([a-zA-Z0-9_-]+)`).FindStringSubmatch(script); len(m) == 2 {
			return normalizeServiceName(m[1])
		}
	}
	if strings.Contains(lower, "--cwd") {
		if m := regexp.MustCompile(`--cwd(?:=|\s+)([^\s]+)`).FindStringSubmatch(script); len(m) == 2 {
			return normalizeServiceName(filepath.Base(strings.Trim(m[1], `"'`)))
		}
	}
	if strings.Contains(lower, "cd ") {
		if m := regexp.MustCompile(`\bcd\s+([^\s&;]+)\s*&&`).FindStringSubmatch(script); len(m) == 2 {
			return normalizeServiceName(filepath.Base(strings.Trim(m[1], `"'`)))
		}
	}
	return ""
}

func inferNodePort(scriptName, scriptBody, dir, logicalName string) (port int, confidence float64, portEnv, ready string) {
	if p, env := inferExplicitPort(scriptBody); p > 0 {
		if env == "" {
			env = inferPortEnv(scriptBody, scriptName)
		}
		return p, 0.98, env, readyPatternForScript(scriptBody, logicalName)
	}

	lower := strings.ToLower(scriptBody)

	if strings.Contains(lower, "vite") {
		if p, ok := inferViteConfigPort(dir); ok {
			return p, 0.9, "", "ready in"
		}
		return 5173, 0.6, "", "ready in"
	}

	if strings.Contains(lower, "next dev") {
		return 3000, 0.6, "PORT", "Ready in"
	}

	if strings.Contains(lower, "react-scripts start") {
		return 3000, 0.6, "PORT", "compiled successfully"
	}

	if strings.Contains(lower, "uvicorn") || strings.Contains(lower, "run_server.py") {
		if p, conf, env := inferPythonLikePort(dir, scriptBody); p > 0 {
			return p, conf, env, "Uvicorn running on"
		}
		return 8000, 0.45, "API_PORT", "Uvicorn running on"
	}
	if strings.Contains(lower, "python ") || strings.Contains(lower, "uv run") {
		if !isLikelyServerScript(scriptName, scriptBody) {
			return 0, 0, "", readyPatternForScript(scriptBody, logicalName)
		}
		if p, conf, env := inferPythonLikePort(dir, scriptBody); p > 0 {
			return p, conf, env, readyPatternForScript(scriptBody, logicalName)
		}
		return 0, 0, "", readyPatternForScript(scriptBody, logicalName)
	}

	return 0, 0, inferPortEnv(scriptBody, scriptName), readyPatternForScript(scriptBody, logicalName)
}

func inferPortEnv(scriptBody, scriptName string) string {
	if m := regexp.MustCompile(`\b([A-Z][A-Z0-9_]+)\s*=\s*\d{2,5}\b`).FindStringSubmatch(scriptBody); len(m) == 2 {
		return m[1]
	}
	lower := strings.ToLower(scriptBody)
	if strings.Contains(lower, "next dev") || strings.Contains(lower, "react-scripts start") {
		return "PORT"
	}
	if strings.Contains(lower, "uvicorn") || strings.Contains(lower, "run_server.py") {
		return "API_PORT"
	}
	if strings.EqualFold(scriptName, "start") || strings.EqualFold(scriptName, "dev") {
		return ""
	}
	return ""
}

func readyPatternForScript(script, logicalName string) string {
	lower := strings.ToLower(script)
	switch {
	case strings.Contains(lower, "vite"):
		return "ready in"
	case strings.Contains(lower, "next dev"):
		return "Ready in"
	case strings.Contains(lower, "uvicorn") || strings.Contains(lower, "run_server.py"):
		return "Uvicorn running on"
	default:
		return guessNodeReady(logicalName)
	}
}

func inferExplicitPort(script string) (port int, env string) {
	if m := regexp.MustCompile(`\b(PORT|API_PORT)\s*=\s*(\d{2,5})\b`).FindStringSubmatch(script); len(m) == 3 {
		return parsePort(m[2]), m[1]
	}
	if m := regexp.MustCompile(`--port(?:=|\s+)(\d{2,5})\b`).FindStringSubmatch(script); len(m) == 2 {
		return parsePort(m[1]), ""
	}
	if m := regexp.MustCompile(`(?:^|\s)-p(?:=|\s+)(\d{2,5})\b`).FindStringSubmatch(script); len(m) == 2 {
		return parsePort(m[1]), ""
	}
	return 0, ""
}

func inferPythonLikePort(dir, script string) (int, float64, string) {
	if p, env := inferExplicitPort(script); p > 0 {
		if env == "" {
			env = "API_PORT"
		}
		return p, 0.98, env
	}

	settingsPath := filepath.Join(dir, "config", "settings.py")
	if data, err := os.ReadFile(settingsPath); err == nil {
		if m := regexp.MustCompile(`API_PORT\s*=\s*int\(\s*os\.getenv\(\s*["']API_PORT["']\s*,\s*["'](\d{2,5})["']\s*\)\s*\)`).FindStringSubmatch(string(data)); len(m) == 2 {
			return parsePort(m[1]), 0.9, "API_PORT"
		}
		if m := regexp.MustCompile(`API_PORT\s*=\s*(\d{2,5})\b`).FindStringSubmatch(string(data)); len(m) == 2 {
			return parsePort(m[1]), 0.85, "API_PORT"
		}
	}

	runServerPath := filepath.Join(dir, "run_server.py")
	if data, err := os.ReadFile(runServerPath); err == nil {
		if m := regexp.MustCompile(`port\s*=\s*(\d{2,5})\b`).FindStringSubmatch(string(data)); len(m) == 2 {
			return parsePort(m[1]), 0.8, "API_PORT"
		}
	}

	if strings.Contains(strings.ToLower(script), "run_server.py") || strings.Contains(strings.ToLower(script), "uvicorn") {
		return 8000, 0.55, "API_PORT"
	}
	return 0, 0, ""
}

func inferViteConfigPort(dir string) (int, bool) {
	for _, name := range []string{"vite.config.ts", "vite.config.js", "vite.config.mjs", "vite.config.cjs"} {
		path := filepath.Join(dir, name)
		data, err := os.ReadFile(path)
		if err != nil {
			continue
		}
		if m := regexp.MustCompile(`(?s)server\s*:\s*\{[^}]*?port\s*:\s*(\d{2,5})`).FindStringSubmatch(string(data)); len(m) == 2 {
			if p := parsePort(m[1]); p > 0 {
				return p, true
			}
		}
	}
	return 0, false
}

func isLikelyServerScript(scriptName, scriptBody string) bool {
	switch strings.ToLower(strings.TrimSpace(scriptName)) {
	case "dev", "start", "start:dev", "serve":
		return true
	}
	lower := strings.ToLower(scriptBody)
	return strings.Contains(lower, "run_server.py") || strings.Contains(lower, "uvicorn")
}

func isLikelyMobilePackage(pkg nodePackageJSON, dir, primaryScript string) bool {
	base := strings.ToLower(filepath.Base(dir))
	if strings.Contains(base, "mobile") {
		return true
	}
	name := strings.ToLower(pkg.Name)
	if strings.Contains(name, "mobile") {
		return true
	}

	all := strings.ToLower(primaryScript)
	for key, val := range pkg.Scripts {
		lk := strings.ToLower(key)
		lv := strings.ToLower(val)
		if strings.Contains(lk, "ios") || strings.Contains(lk, "android") || strings.Contains(lk, "eas") {
			return true
		}
		all += " " + lk + " " + lv
	}
	if strings.Contains(all, "expo start") || strings.Contains(all, "expo run:") {
		return true
	}
	return false
}

func isOrchestratorScript(script string) bool {
	lower := strings.ToLower(script)
	for _, marker := range []string{
		"turbo run",
		"nx run-many",
		"lerna run",
		"pnpm -r",
		"pnpm --recursive",
		"yarn workspaces",
	} {
		if strings.Contains(lower, marker) {
			return true
		}
	}
	return false
}

func isTargetedScript(script string) bool {
	lower := strings.ToLower(script)
	if strings.Contains(lower, "--filter") || strings.Contains(lower, "--cwd") {
		return true
	}
	return regexp.MustCompile(`\bcd\s+[^\s&;]+\s*&&`).MatchString(lower)
}

func detectPackageManager(dir, packageManager, fallback string) string {
	if pm := packageManagerFromField(packageManager); pm != "" {
		return pm
	}
	if _, err := os.Stat(filepath.Join(dir, "bun.lock")); err == nil {
		return "bun"
	}
	if _, err := os.Stat(filepath.Join(dir, "bun.lockb")); err == nil {
		return "bun"
	}
	if _, err := os.Stat(filepath.Join(dir, "pnpm-lock.yaml")); err == nil {
		return "pnpm"
	}
	if _, err := os.Stat(filepath.Join(dir, "yarn.lock")); err == nil {
		return "yarn"
	}
	if _, err := os.Stat(filepath.Join(dir, "package-lock.json")); err == nil {
		return "npm"
	}
	if fallback != "" {
		return fallback
	}
	return "npm"
}

func packageManagerFromField(raw string) string {
	raw = strings.TrimSpace(raw)
	if raw == "" {
		return ""
	}
	base := raw
	if idx := strings.Index(base, "@"); idx > 0 {
		base = base[:idx]
	}
	base = strings.ToLower(strings.TrimSpace(base))
	switch base {
	case "bun", "pnpm", "yarn", "npm":
		return base
	default:
		return ""
	}
}

func resolveWorkspaceDirs(root string, raw json.RawMessage) []string {
	patterns := parseWorkspacePatterns(raw)
	seen := make(map[string]struct{})
	out := make([]string, 0)

	for _, pattern := range patterns {
		glob := filepath.Join(root, filepath.FromSlash(pattern))
		matches, err := filepath.Glob(glob)
		if err != nil {
			continue
		}
		for _, m := range matches {
			if !isPackageDir(m) {
				continue
			}
			if strings.Contains(filepath.ToSlash(m), "/node_modules/") {
				continue
			}
			if _, ok := seen[m]; ok {
				continue
			}
			seen[m] = struct{}{}
			out = append(out, m)
		}
	}

	if len(out) == 0 {
		for _, p := range fallbackPackageDirs(root) {
			if _, ok := seen[p]; ok {
				continue
			}
			seen[p] = struct{}{}
			out = append(out, p)
		}
	}

	sort.Strings(out)
	return out
}

func fallbackPackageDirs(root string) []string {
	seen := make(map[string]struct{})
	out := make([]string, 0)

	for _, g := range []string{"apps/*", "packages/*", "services/*"} {
		matches, err := filepath.Glob(filepath.Join(root, filepath.FromSlash(g)))
		if err != nil {
			continue
		}
		for _, m := range matches {
			if isPackageDir(m) {
				seen[m] = struct{}{}
			}
		}
	}

	for _, sub := range []string{"frontend", "client", "web", "app", "backend", "server", "api"} {
		p := filepath.Join(root, sub)
		if isPackageDir(p) {
			seen[p] = struct{}{}
		}
	}

	for p := range seen {
		out = append(out, p)
	}
	sort.Strings(out)
	return out
}

func isPackageDir(path string) bool {
	info, err := os.Stat(path)
	if err != nil || !info.IsDir() {
		return false
	}
	if _, err := os.Stat(filepath.Join(path, "package.json")); err != nil {
		return false
	}
	return true
}

func parseWorkspacePatterns(raw json.RawMessage) []string {
	if len(raw) == 0 {
		return nil
	}

	var list []string
	if err := json.Unmarshal(raw, &list); err == nil {
		return sanitizeWorkspacePatterns(list)
	}

	var obj struct {
		Packages []string `json:"packages"`
	}
	if err := json.Unmarshal(raw, &obj); err == nil {
		return sanitizeWorkspacePatterns(obj.Packages)
	}

	return nil
}

func sanitizeWorkspacePatterns(patterns []string) []string {
	seen := make(map[string]struct{})
	out := make([]string, 0, len(patterns))
	for _, p := range patterns {
		p = strings.TrimSpace(p)
		if p == "" {
			continue
		}
		p = filepath.ToSlash(p)
		if _, ok := seen[p]; ok {
			continue
		}
		seen[p] = struct{}{}
		out = append(out, p)
	}
	sort.Strings(out)
	return out
}

func inferServiceName(prefix, pkgName, dir string) string {
	if prefix != "" {
		return prefix
	}
	if pkgName != "" {
		if idx := strings.LastIndex(pkgName, "/"); idx >= 0 {
			pkgName = pkgName[idx+1:]
		}
		return pkgName
	}
	return filepath.Base(dir)
}

func normalizeServiceName(s string) string {
	s = strings.ToLower(strings.TrimSpace(s))
	if s == "" {
		return ""
	}
	re := regexp.MustCompile(`[^a-z0-9]+`)
	s = re.ReplaceAllString(s, "-")
	s = strings.Trim(s, "-")
	s = regexp.MustCompile(`-+`).ReplaceAllString(s, "-")
	return s
}

func guessNodeReady(name string) string {
	lower := strings.ToLower(name)
	switch {
	case strings.Contains(lower, "frontend") || strings.Contains(lower, "client") || strings.Contains(lower, "web"):
		return "compiled successfully"
	case strings.Contains(lower, "backend") || strings.Contains(lower, "server") || strings.Contains(lower, "api"):
		return "listening on"
	}
	return "ready"
}

func parsePort(s string) int {
	s = strings.TrimSpace(s)
	n, err := strconv.Atoi(s)
	if err != nil {
		return 0
	}
	if n > 0 && n < 65536 {
		return n
	}
	return 0
}
