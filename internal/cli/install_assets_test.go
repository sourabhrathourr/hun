package cli

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestInstallScriptPrintsOnboardingWelcome(t *testing.T) {
	path := filepath.Join("..", "..", "website", "public", "install.sh")
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("read install script: %v", err)
	}
	text := string(data)
	if !strings.Contains(text, "Welcome to hun.") {
		t.Fatalf("install script missing welcome message")
	}
	if !strings.Contains(text, "hun onboard") {
		t.Fatalf("install script missing onboarding next step")
	}
}

func TestHomebrewFormulaTemplateIncludesCaveats(t *testing.T) {
	path := filepath.Join("..", "..", "scripts", "update-homebrew-formula.sh")
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("read formula script: %v", err)
	}
	text := string(data)
	if !strings.Contains(text, "def caveats") {
		t.Fatalf("formula template missing caveats block")
	}
	if !strings.Contains(text, "hun onboard") {
		t.Fatalf("formula caveats missing onboarding hint")
	}
}
