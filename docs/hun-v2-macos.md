# hun v2 and macOS App TODOs

## Product Direction

- [ ] Keep hun centered on easy project-level context switching.
- [ ] Treat the macOS app as a native control center, not just a GUI version of the TUI.
- [ ] Keep the existing daemon as the source of truth for projects, services, logs, ports, and state.
- [ ] Preserve the CLI and TUI as first-class interfaces.

## hun v2 Core

- [ ] Define a richer project context model in state.
- [ ] Track the active project, mode, services, ports, branch, and last note consistently.
- [ ] Add first-class support for project handoff notes.
- [ ] Allow users to write a note before switching away from a project.
- [ ] Store the latest handoff note per project.
- [ ] Show the saved handoff note when switching back to a project.
- [ ] Add an API endpoint for reading and writing project handoff context.
- [ ] Add an API endpoint for recent logs per project and service.
- [ ] Add an API endpoint for current git branch and dirty status.
- [ ] Keep Focus mode simple: stop other projects, start the target project.
- [ ] Keep Multitask mode simple: run projects side by side with port offsets.
- [ ] Make state migrations explicit as the project context model grows.

## Auto Handoff

- [ ] Generate a handoff summary when switching away from a project.
- [ ] Include current git branch in the generated handoff.
- [ ] Include dirty git status in the generated handoff.
- [ ] Include recent service status in the generated handoff.
- [ ] Include failing services in the generated handoff.
- [ ] Include recent error-looking log lines in the generated handoff.
- [ ] Include the user's manual note when provided.
- [ ] Prefer concise summaries over long logs.
- [ ] Let users edit the generated handoff before saving.
- [ ] Show both the generated handoff and manual note on resume.

## macOS Menu Bar App

- [ ] Build a lightweight SwiftUI menu bar app.
- [ ] Show the active project in the menu bar.
- [ ] Show a compact running/stopped/error status indicator.
- [ ] List registered projects in the menu bar popover.
- [ ] Switch projects directly from the menu bar.
- [ ] Run a project in Multitask mode from the menu bar.
- [ ] Stop the active project from the menu bar.
- [ ] Stop all projects from the menu bar.
- [ ] Restart a project from the menu bar.
- [ ] Restart an individual service from the menu bar.
- [ ] Open the focused project's logs from the menu bar.
- [ ] Surface the latest handoff note in the menu bar popover.

## macOS Command Palette

- [ ] Add a global hotkey for opening hun.
- [ ] Build a native command palette.
- [ ] Fuzzy search projects.
- [ ] Switch to a project from the palette.
- [ ] Start a project alongside the current one from the palette.
- [ ] Stop projects from the palette.
- [ ] Restart services from the palette.
- [ ] Copy recent logs from the palette.
- [ ] Save a handoff note from the palette.
- [ ] Keep command execution fast enough to feel instant.

## macOS Main Window

- [ ] Build a main project dashboard.
- [ ] Show projects in a sidebar.
- [ ] Show services for the selected project.
- [ ] Show service status, PID, and port.
- [ ] Show project logs with search and filtering.
- [ ] Support copying selected log lines.
- [ ] Support combined logs across services.
- [ ] Support Focus and Multitask mode switching.
- [ ] Show saved handoff context for each project.
- [ ] Let users edit the current project's handoff note.

## Notifications

- [ ] Notify when a project finishes starting.
- [ ] Notify when a service crashes.
- [ ] Notify when a switch completes.
- [ ] Notify when a generated handoff contains a likely error.
- [ ] Keep notifications quiet by default.
- [ ] Add preferences for notification types.

## macOS Integration

- [ ] Launch the app at login.
- [ ] Add a preferences screen.
- [ ] Let users configure global hotkeys.
- [ ] Let users choose whether the app starts the daemon automatically.
- [ ] Package the app with the hun CLI/daemon.
- [ ] Handle daemon version mismatches cleanly.
- [ ] Add a simple onboarding flow for existing hun users.

## Not In Scope

- [ ] Do not add project launch links for app/admin/API/docs/db/repo/issue trackers.
- [ ] Do not add local dev health checks beyond existing service status, logs, and ports.
