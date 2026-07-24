#!/bin/zsh

set -u

repo_root=${0:A:h:h}
project_path="$repo_root/apps/macos/hun/hun.xcodeproj"
source_path="$repo_root/apps/macos/hun/hun"
derived_data_path="$repo_root/.build/xcode-dev"
app_path="$derived_data_path/Build/Products/Debug/hun.app"
executable_path="$app_path/Contents/MacOS/hun"
bundle_identifier="sourabh.fun.hun.dev"
watch_paths=(
	"$source_path"
	"$repo_root/cmd"
	"$repo_root/internal"
	"$repo_root/skills/hun"
)

snapshot() {
	{
		find "${watch_paths[@]}" -type f -exec shasum {} +
		shasum \
			"$project_path/project.pbxproj" \
			"$repo_root/go.mod" \
			"$repo_root/go.sum"
	} | sort | shasum | awk '{ print $1 }'
}

build_app() {
	echo
	echo "Building hun Dev…"
	xcodebuild \
		-quiet \
		-project "$project_path" \
		-scheme hun \
		-configuration Debug \
		-destination "platform=macOS,arch=$(uname -m)" \
		-derivedDataPath "$derived_data_path" \
		CODE_SIGNING_ALLOWED=NO \
		build
}

relaunch_app() {
	# Quit a Debug app previously launched by Xcode as well as one launched by
	# this watcher. The release app uses a different bundle identifier.
	osascript -e "tell application id \"$bundle_identifier\" to quit" >/dev/null 2>&1 || true

	# Match the executable inside this dedicated DerivedData directory so a
	# stuck watcher-owned process can be terminated without touching release.
	pkill -TERM -x -f "$executable_path" >/dev/null 2>&1 || true

	local attempts=0
	while pgrep -x -f "$executable_path" >/dev/null 2>&1 && (( attempts < 20 )); do
		sleep 0.05
		(( attempts += 1 ))
	done

	open -n "$app_path"
	echo "Launched hun Dev. Watching for changes — press Ctrl-C to stop."
}

last_built_snapshot=""

while true; do
	current_snapshot=$(snapshot)

	if [[ "$current_snapshot" != "$last_built_snapshot" ]]; then
		# Let Xcode finish atomic saves and coalesce nearby edits into one build.
		sleep 0.25
		current_snapshot=$(snapshot)

		if build_app; then
			relaunch_app
		else
			echo
			echo "Build failed. Fix the error and save to try again."
		fi

		# If a file changes while xcodebuild is running, the next loop sees a
		# different snapshot and immediately starts another build.
		last_built_snapshot="$current_snapshot"
	fi

	sleep 0.5
done
