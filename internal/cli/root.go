package cli

import (
	"errors"

	"github.com/sourabhrathourr/hun/internal/state"
	"github.com/spf13/cobra"
)

var multiFlag bool

var rootCmd = &cobra.Command{
	Use:   "hun",
	Short: "Seamless project context switching for developers",
	Long:  "hun.sh manages your development services, captures logs, and lets you switch between projects instantly.",
	RunE: func(cmd *cobra.Command, args []string) error {
		if st, err := state.Load(); err == nil && shouldPromptAutoOnboard(isInteractiveTerminal(), len(st.Registry)) {
			ok, confirmErr := confirmPrompt("No projects registered. Start onboarding now? [Y/n] ")
			if confirmErr != nil {
				return confirmErr
			}
			if ok {
				result, onboardErr := runOnboardingFlow(onboardingOptions{})
				if onboardErr != nil {
					if errors.Is(onboardErr, errOnboardingCanceled) {
						return launchTUI(multiFlag)
					}
					return onboardErr
				}
				if result.Completed || result.LaunchedTUI {
					return nil
				}
			}
		}

		// If no subcommand, launch TUI
		return launchTUI(multiFlag)
	},
}

func init() {
	rootCmd.Flags().BoolVar(&multiFlag, "multi", false, "Open TUI in Multitask Mode")
}

func Execute() error {
	return rootCmd.Execute()
}
