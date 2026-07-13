#!/bin/bash

set -euo pipefail
IFS=$'\n\t'
umask 077

readonly EXPECTED_BUNDLE_ID="app.choatelabs.bitecast"
readonly EXPECTED_TEAM_ID="RAYW3WPJ98"
readonly REQUIRED_SIMULATOR_RUNTIME="com.apple.CoreSimulator.SimRuntime.iOS-26-5"
readonly REQUIRED_SIMULATOR_NAME="iPhone 17 Pro"
readonly PHYSICAL_XCODE_DESTINATION_ID="00008140-0006153E3C3B801C"
readonly PHYSICAL_PROTECTION_TEST_SELECTOR="BiteCastTests/CatchProtectionDeviceTests/physicalCatchTransactionUsesCompleteFileProtection"
readonly PREFERENCES_RELATIVE_PATH="Library/Preferences/app.choatelabs.bitecast.plist"

MODE="full"
ALLOW_DIRTY=0
ALLOW_PROVISIONING_UPDATES=0
RUN_EXPORT=0
DEVICE_ID=""

usage() {
    cat <<'USAGE'
Usage: Scripts/release_gate.sh [options]

Runs a clean, reproducible BiteCast release gate. With no options it runs the
full local gate through a signed Release archive. Network-backed App Store
export and physical-device release proof are explicit because they change external
state.

Options:
  --preflight
      Run only generation, lint, configuration, media, and secret-boundary
      checks. Does not compile, test, archive, export, or touch a device.
  --allow-dirty
      Permit a dirty repository for --preflight only. A full gate always
      requires a clean repository so its evidence maps to one commit.
  --allow-provisioning-updates
      Let xcodebuild contact Apple to create/download automatic-signing assets.
  --export
      Optional: attempt a local App Store Connect export after archiving.
      Requires --allow-provisioning-updates. This never uploads or submits the
      app; when omitted, the gate records the export as not-attempted.
  --install-device <CoreDevice identifier>
      Run the complete guarded physical-device evidence flow. BiteCast must
      already be installed. A newer build upgrades; an equal build is an
      explicit idempotent reinstall; a downgrade is rejected. The gate proves
      preferences and the data container survive two Release installs around
      the physical file-protection test, then launches and screenshots the app.
      This never uninstalls, erases, or resets app data.
  --help
      Show this help.

Complete Task 12F invocation:
  Scripts/release_gate.sh --allow-provisioning-updates --export \
    --install-device F711A3B1-8E23-5E3F-80C0-3178F9883433
USAGE
}

die() {
    printf 'release gate: ERROR: %s\n' "$*" >&2
    exit 1
}

note() {
    printf '\n==> %s\n' "$*"
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || die "required command is missing: $1"
}

run_logged() {
    local log_path="$1"
    local -a pipeline_status
    shift
    mkdir -p "$(dirname "$log_path")"
    set +e
    "$@" 2>&1 | tee "$log_path"
    pipeline_status=("${PIPESTATUS[@]}")
    set -e
    if [[ "${pipeline_status[0]}" -ne 0 ]]; then
        return "${pipeline_status[0]}"
    fi
    if [[ "${pipeline_status[1]}" -ne 0 ]]; then
        return "${pipeline_status[1]}"
    fi
    [[ -f "$log_path" && ! -L "$log_path" ]] || {
        printf 'release gate: command log is not a regular file: %s\n' \
            "$log_path" >&2
        return 1
    }
}

plist_value() {
    local plist="$1"
    local key_path="$2"
    plutil -extract "$key_path" raw "$plist"
}

plistbuddy_value() {
    local plist="$1"
    local key_path="$2"
    /usr/libexec/PlistBuddy -c "Print $key_path" "$plist"
}

assert_equal() {
    local actual="$1"
    local expected="$2"
    local description="$3"
    [[ "$actual" == "$expected" ]] || {
        die "$description: expected '$expected', found '$actual'"
    }
}

link_project_input() {
    local source_path="$1"
    local destination_path="$2"

    [[ -e "$source_path" ]] || die "project input is missing: $source_path"
    if [[ -L "$destination_path" ]]; then
        assert_equal "$(readlink "$destination_path")" "$source_path" \
            "isolated-project link target for $destination_path"
        return
    fi
    [[ ! -e "$destination_path" ]] || {
        die "refusing to replace unexpected project input path: $destination_path"
    }
    ln -s "$source_path" "$destination_path"
    [[ -L "$destination_path" ]] || {
        die "failed to create isolated-project link: $destination_path"
    }
}

create_evidence_run() {
    local mode="$1"
    local created
    local canonical

    created="$(mktemp -d "/private/tmp/bitecast-release-gate.${mode}.XXXXXXXX")"
    canonical="$(cd "$created" && pwd -P)"
    case "$canonical" in
        /private/tmp/bitecast-release-gate."$mode".*) ;;
        *) die "mktemp returned a noncanonical evidence path: $canonical" ;;
    esac
    [[ -d "$canonical" && ! -L "$canonical" ]] || {
        die "evidence path is not a real directory: $canonical"
    }
    printf '%s\n' "$canonical"
}

create_head_snapshot() {
    local repository="$1"
    local revision="$2"
    local archive_path="$3"
    local snapshot_path="$4"
    local checksum_path="$5"

    [[ ! -e "$archive_path" && ! -L "$archive_path" ]] || {
        die "snapshot archive path already exists: $archive_path"
    }
    [[ ! -e "$snapshot_path" && ! -L "$snapshot_path" ]] || {
        die "snapshot directory path already exists: $snapshot_path"
    }
    mkdir -p "$snapshot_path"
    git -C "$repository" archive --format=tar \
        --output="$archive_path" "$revision"
    shasum -a 256 "$archive_path" > "$checksum_path"
    tar -xf "$archive_path" -C "$snapshot_path"
}

run_xcode_with_optional_provisioning() {
    local log_path="$1"
    shift
    if [[ "$ALLOW_PROVISIONING_UPDATES" -eq 1 ]]; then
        run_logged "$log_path" "$@" -allowProvisioningUpdates
    else
        run_logged "$log_path" "$@"
    fi
}

assert_rg_no_matches() {
    local description="$1"
    local output_path="$2"
    shift 2
    local error_path="${output_path}.stderr"
    local rg_status=0

    rg "$@" > "$output_path" 2> "$error_path" || rg_status=$?
    case "$rg_status" in
        0)
            cat "$output_path" >&2
            die "$description found forbidden content"
            ;;
        1)
            return 0
            ;;
        *)
            cat "$error_path" >&2
            die "$description could not complete (rg status $rg_status)"
            ;;
    esac
}

classify_install_build() {
    local candidate="$1"
    local installed="$2"

    [[ "$candidate" =~ ^[0-9]+$ && "$installed" =~ ^[0-9]+$ ]] || return 2
    if (( 10#$candidate < 10#$installed )); then
        printf 'downgrade\n'
    elif (( 10#$candidate == 10#$installed )); then
        printf 'idempotent-reinstall\n'
    else
        printf 'upgrade\n'
    fi
}

assert_physical_test_result() {
    local summary_path="$1"
    local tests_path="$2"
    local expected_leaf="${PHYSICAL_PROTECTION_TEST_SELECTOR#BiteCastTests/}"

    jq empty "$summary_path" || die "physical-test summary JSON is malformed"
    jq empty "$tests_path" || die "physical-test detail JSON is malformed"
    jq -e \
        --arg device_id "$PHYSICAL_XCODE_DESTINATION_ID" \
        '.result == "Passed"
         and .totalTestCount == 1
         and .passedTests == 1
         and .failedTests == 0
         and .skippedTests == 0
         and .expectedFailures == 0
         and (.devicesAndConfigurations | length) == 1
         and .devicesAndConfigurations[0].device.deviceId == $device_id
         and .devicesAndConfigurations[0].device.platform == "iOS"' \
        "$summary_path" >/dev/null || {
        die "physical-test summary does not prove exactly one passed hardware test"
    }
    jq -e \
        --arg expected_leaf "$expected_leaf" \
        '[.. | objects | select(.nodeType? == "Test Case")] as $tests
         | ($tests | length) == 1
           and $tests[0].result == "Passed"
           and ([
               ($tests[0].nodeIdentifier // ""),
               ($tests[0].nodeIdentifierURL // "")
           ] | join("\n") | contains($expected_leaf))' \
        "$tests_path" >/dev/null || {
        die "physical-test details do not identify the required passed selector"
    }
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --preflight)
            MODE="preflight"
            shift
            ;;
        --allow-dirty)
            ALLOW_DIRTY=1
            shift
            ;;
        --allow-provisioning-updates)
            ALLOW_PROVISIONING_UPDATES=1
            shift
            ;;
        --export)
            RUN_EXPORT=1
            shift
            ;;
        --install-device)
            [[ $# -ge 2 ]] || die "--install-device requires an identifier"
            DEVICE_ID="$2"
            shift 2
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            die "unknown option: $1"
            ;;
    esac
done

if [[ "$MODE" != "preflight" && "$ALLOW_DIRTY" -eq 1 ]]; then
    die "--allow-dirty is permitted only with --preflight"
fi
if [[ "$MODE" == "preflight" && "$RUN_EXPORT" -eq 1 ]]; then
    die "--export cannot be combined with --preflight"
fi
if [[ "$MODE" == "preflight" && -n "$DEVICE_ID" ]]; then
    die "--install-device cannot be combined with --preflight"
fi
if [[ "$MODE" == "preflight" && "$ALLOW_PROVISIONING_UPDATES" -eq 1 ]]; then
    die "--allow-provisioning-updates cannot be combined with --preflight"
fi
if [[ "$RUN_EXPORT" -eq 1 && "$ALLOW_PROVISIONING_UPDATES" -ne 1 ]]; then
    die "--export requires --allow-provisioning-updates"
fi

SCRIPT_DIR=""
LIVE_APP_ROOT=""
REPO_ROOT=""
SOURCE_GIT_SHA=""
SOURCE_STATUS=""
if ! SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"; then
    die "could not resolve the release-gate script directory"
fi
if ! LIVE_APP_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"; then
    die "could not resolve the application root"
fi
if ! REPO_ROOT="$(git -C "$LIVE_APP_ROOT" rev-parse --show-toplevel)"; then
    die "could not resolve the repository root"
fi
if ! SOURCE_GIT_SHA="$(git -C "$REPO_ROOT" rev-parse HEAD)"; then
    die "could not resolve the source commit"
fi
[[ "$SOURCE_GIT_SHA" =~ ^[0-9a-fA-F]{40,64}$ ]] || {
    die "source commit has an invalid object identifier: $SOURCE_GIT_SHA"
}
if ! SOURCE_STATUS="$(git -C "$REPO_ROOT" \
    status --porcelain --untracked-files=all)"; then
    die "could not inspect the source-tree status"
fi
readonly SCRIPT_DIR LIVE_APP_ROOT REPO_ROOT SOURCE_GIT_SHA SOURCE_STATUS

if [[ -n "$SOURCE_STATUS" && "$ALLOW_DIRTY" -ne 1 ]]; then
    printf '%s\n' "$SOURCE_STATUS" >&2
    die "repository is dirty; commit or stash changes before producing release evidence"
fi
if [[ -n "$SOURCE_STATUS" ]]; then
    note "Dirty-tree override is active for this preflight-only run"
fi

for command_name in awk date diff find git grep jq ln mktemp plutil readlink rg sed \
    sort strings tar tee tr xcodebuild xcodegen xcrun; do
    require_command "$command_name"
done
[[ -x /usr/libexec/PlistBuddy ]] || die "PlistBuddy is unavailable"

if [[ "$MODE" == "full" ]]; then
    for command_name in codesign security shasum sleep stat; do
        require_command "$command_name"
    done
    [[ -x /usr/bin/ditto ]] || die "ditto is unavailable"
fi

RUN_ROOT=""
if ! RUN_ROOT="$(create_evidence_run "$MODE")"; then
    die "could not create the private evidence directory"
fi
[[ -n "$RUN_ROOT" ]] || die "private evidence directory path is empty"
readonly RUN_ROOT
readonly PROJECT_DIR="$RUN_ROOT/project"
readonly PROJECT="$PROJECT_DIR/BiteCast.xcodeproj"
readonly LOG_DIR="$RUN_ROOT/logs"
readonly RESULT_DIR="$RUN_ROOT/results"
readonly AUDIT_DIR="$RUN_ROOT/audit"
ACTIVE_PRIVATE_COPY_DIR=""

scrub_active_private_copy() {
    local private_dir="$ACTIVE_PRIVATE_COPY_DIR"

    [[ -n "$private_dir" ]] || return 0
    case "$private_dir" in
        /private/tmp/bitecast-release-private.*) ;;
        *)
            printf 'release gate: refusing to scrub unexpected private path: %s\n' \
                "$private_dir" >&2
            return 1
            ;;
    esac
    [[ ! -L "$private_dir" ]] || {
        printf 'release gate: refusing to follow private-copy symlink: %s\n' \
            "$private_dir" >&2
        return 1
    }
    if [[ -d "$private_dir" ]]; then
        find -P "$private_dir" -depth -delete || return 1
    fi
    ACTIVE_PRIVATE_COPY_DIR=""
}

record_failed_run() {
    local exit_status=$?
    local scrub_status=0

    trap - EXIT
    set +e
    scrub_active_private_copy
    scrub_status=$?
    if [[ "$scrub_status" -ne 0 && "$exit_status" -eq 0 ]]; then
        exit_status=1
    fi
    if [[ "$exit_status" -ne 0 && -d "$RUN_ROOT" ]]; then
        printf 'exit_status=%s\n' "$exit_status" > "$RUN_ROOT/gate-exit-status.txt"
        printf 'Release-gate evidence preserved at: %s\n' "$RUN_ROOT" >&2
    fi
    exit "$exit_status"
}
trap record_failed_run EXIT

mkdir -p "$PROJECT_DIR" "$LOG_DIR" "$RESULT_DIR" "$AUDIT_DIR"
printf 'Evidence directory: %s\n' "$RUN_ROOT"
cat > "$RUN_ROOT/run-identity.txt" <<IDENTITY
mode=$MODE
git_sha=$SOURCE_GIT_SHA
created_utc=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
IDENTITY

BUILD_APP_ROOT="$LIVE_APP_ROOT"
if [[ "$MODE" == "full" ]]; then
    readonly SOURCE_ARCHIVE="$RUN_ROOT/source-head.tar"
    readonly SNAPSHOT_REPO_ROOT="$RUN_ROOT/source"
    create_head_snapshot \
        "$REPO_ROOT" "$SOURCE_GIT_SHA" "$SOURCE_ARCHIVE" \
        "$SNAPSHOT_REPO_ROOT" "$AUDIT_DIR/source-head.tar.sha256"
    BUILD_APP_ROOT="$SNAPSHOT_REPO_ROOT/FishingWeather"
    [[ -d "$BUILD_APP_ROOT" ]] || {
        die "HEAD snapshot does not contain FishingWeather"
    }
fi
readonly BUILD_APP_ROOT

assert_live_source_unchanged() {
    local checkpoint="$1"
    local current_head
    local current_status

    [[ "$MODE" == "full" ]] || return 0
    current_head="$(git -C "$REPO_ROOT" rev-parse HEAD)"
    current_status="$(git -C "$REPO_ROOT" status --porcelain --untracked-files=all)"
    assert_equal "$current_head" "$SOURCE_GIT_SHA" \
        "$checkpoint source commit"
    [[ -z "$current_status" ]] || {
        printf '%s\n' "$current_status" >&2
        die "$checkpoint requires the source tree to remain clean"
    }
    printf 'checkpoint=%s\nhead=%s\ntree=clean\n---\n' \
        "$checkpoint" "$current_head" \
        >> "$AUDIT_DIR/source-integrity-checkpoints.txt"
}

capture_device_app_state() {
    local output_path="$1"
    local phase="$2"

    [[ ! -e "$output_path" && ! -L "$output_path" ]] || {
        die "device-app evidence already exists: $output_path"
    }
    run_logged "$LOG_DIR/device-app-$phase.log" \
        xcrun devicectl device info apps \
        --device "$DEVICE_ID" \
        --bundle-id "$EXPECTED_BUNDLE_ID" \
        --require-container-access \
        --include-container-paths \
        --json-output "$output_path" \
        --log-output "$LOG_DIR/device-app-$phase-devicectl.log" \
        --timeout 30
    [[ -f "$output_path" && ! -L "$output_path" ]] || {
        die "$phase device-app query produced no JSON evidence"
    }
    jq empty "$output_path" || die "$phase device-app JSON is malformed"
    jq -e '.result.apps | type == "array"' "$output_path" >/dev/null || {
        die "$phase device-app JSON has no application result array"
    }
    assert_equal "$(jq -r '.result.apps | length' "$output_path")" \
        "1" "$phase installed BiteCast app count"
    assert_equal "$(jq -r '.result.apps[0].bundleIdentifier' "$output_path")" \
        "$EXPECTED_BUNDLE_ID" "$phase installed BiteCast bundle identifier"
    [[ "$(jq -r '.result.apps[0].bundleVersion' "$output_path")" =~ ^[0-9]+$ ]] || {
        die "$phase installed build number is not numeric"
    }
    [[ "$(jq -r '.result.apps[0].dataContainerPath' "$output_path")" != "null" \
        && -n "$(jq -r '.result.apps[0].dataContainerPath' "$output_path")" ]] || {
        die "$phase app data container is not accessible"
    }
}

capture_preferences_fingerprint() {
    local phase="$1"
    local fingerprint_path="$2"
    local created_private_dir
    local private_dir
    local private_plist
    local preference_hash
    local preference_size

    [[ ! -e "$fingerprint_path" && ! -L "$fingerprint_path" ]] || {
        die "preferences fingerprint evidence already exists: $fingerprint_path"
    }
    created_private_dir="$(mktemp -d \
        '/private/tmp/bitecast-release-private.XXXXXXXX')"
    private_dir="$(cd "$created_private_dir" && pwd -P)"
    case "$private_dir" in
        /private/tmp/bitecast-release-private.*) ;;
        *) die "mktemp returned an unexpected private-copy path: $private_dir" ;;
    esac
    [[ -d "$private_dir" && ! -L "$private_dir" ]] || {
        die "private-copy path is not a real directory: $private_dir"
    }
    ACTIVE_PRIVATE_COPY_DIR="$private_dir"
    private_plist="$private_dir/preferences.plist"

    if ! run_logged "$LOG_DIR/device-preferences-$phase-copy.log" \
        xcrun devicectl device copy from \
        --device "$DEVICE_ID" \
        --domain-type appDataContainer \
        --domain-identifier "$EXPECTED_BUNDLE_ID" \
        --source "$PREFERENCES_RELATIVE_PATH" \
        --destination "$private_plist" \
        --json-output "$AUDIT_DIR/device-preferences-$phase-copy.json" \
        --log-output "$LOG_DIR/device-preferences-$phase-devicectl.log" \
        --timeout 30; then
        scrub_active_private_copy || true
        die "$phase preferences copy failed"
    fi
    [[ -f "$private_plist" && ! -L "$private_plist" ]] || {
        scrub_active_private_copy || true
        die "$phase preferences copy did not produce one regular plist"
    }

    preference_hash="$(shasum -a 256 "$private_plist" | awk '{ print $1 }')"
    preference_size="$(stat -f '%z' "$private_plist")"
    [[ "$preference_hash" =~ ^[0-9a-fA-F]{64}$ ]] || {
        die "$phase preferences SHA-256 could not be computed"
    }
    [[ "$preference_size" =~ ^[0-9]+$ ]] || {
        die "$phase preferences size could not be computed"
    }
    cat > "$fingerprint_path" <<FINGERPRINT
sha256=$preference_hash
size_bytes=$preference_size
FINGERPRINT

    scrub_active_private_copy || {
        die "$phase private preferences copy could not be scrubbed"
    }
    [[ ! -e "$private_dir" && ! -L "$private_dir" ]] || {
        die "$phase private preferences directory still exists after scrubbing"
    }
}

assert_preferences_unchanged() {
    local baseline_path="$1"
    local candidate_path="$2"
    local phase="$3"
    local proof_path="$AUDIT_DIR/device-preferences-$phase-proof.txt"
    local diff_path="$AUDIT_DIR/device-preferences-$phase.diff"

    if ! diff -u "$baseline_path" "$candidate_path" > "$diff_path"; then
        cat "$diff_path" >&2
        die "$phase preferences hash or size changed"
    fi
    cat > "$proof_path" <<PROOF
baseline_sha256=$(awk -F= '$1 == "sha256" { print $2 }' "$baseline_path")
candidate_sha256=$(awk -F= '$1 == "sha256" { print $2 }' "$candidate_path")
baseline_size_bytes=$(awk -F= '$1 == "size_bytes" { print $2 }' "$baseline_path")
candidate_size_bytes=$(awk -F= '$1 == "size_bytes" { print $2 }' "$candidate_path")
match=passed
PROOF
}

launch_device_with_bounded_console() {
    local console_output="$AUDIT_DIR/device-launch-console.txt"
    local launch_json="$AUDIT_DIR/device-launch-console.json"
    local launch_log="$LOG_DIR/device-launch-devicectl.log"
    local watchdog_marker="$AUDIT_DIR/device-launch-watchdog.txt"
    local foreground_json="$AUDIT_DIR/device-launch-foreground.json"
    local launch_pid
    local watchdog_pid
    local launch_status=0

    assert_live_source_unchanged "physical-device launch"
    set +e
    xcrun devicectl device process launch \
        --device "$DEVICE_ID" \
        --activate \
        --console \
        --json-output "$launch_json" \
        --log-output "$launch_log" \
        --timeout 30 \
        "$EXPECTED_BUNDLE_ID" > "$console_output" 2>&1 &
    launch_pid=$!
    (
        sleep 12
        if kill -0 "$launch_pid" 2>/dev/null; then
            if kill -TERM "$launch_pid" 2>/dev/null; then
                printf 'bounded_console_seconds=12\n' > "$watchdog_marker"
            fi
        fi
    ) &
    watchdog_pid=$!
    wait "$launch_pid"
    launch_status=$?
    kill "$watchdog_pid" 2>/dev/null || true
    wait "$watchdog_pid" 2>/dev/null || true
    set -e

    if [[ "$launch_status" -ne 0 && ! -f "$watchdog_marker" ]]; then
        cat "$console_output" >&2
        die "physical-device launch or console attachment failed"
    fi
    if [[ "$launch_status" -eq 0 ]]; then
        [[ -s "$launch_json" ]] || {
            die "physical-device launch produced no JSON result"
        }
        jq empty "$launch_json" || {
            die "physical-device launch JSON is malformed"
        }
    fi
    [[ -s "$console_output" || -s "$launch_log" ]] || {
        die "physical-device launch produced no console or devicectl log"
    }

    # A signal used to bound --console is forwarded to the app. Relaunch once
    # without console attachment so the screenshot proves the foreground app,
    # not a home-screen fallback after the bounded capture ends.
    assert_live_source_unchanged "physical-device foreground relaunch"
    run_logged "$LOG_DIR/device-launch-foreground.log" \
        xcrun devicectl device process launch \
        --device "$DEVICE_ID" \
        --activate \
        --terminate-existing \
        --json-output "$foreground_json" \
        --log-output "$LOG_DIR/device-launch-foreground-devicectl.log" \
        --timeout 30 \
        "$EXPECTED_BUNDLE_ID"
    [[ -s "$foreground_json" ]] || {
        die "physical-device foreground relaunch produced no JSON result"
    }
    jq empty "$foreground_json" || {
        die "physical-device foreground relaunch JSON is malformed"
    }
    cat > "$AUDIT_DIR/device-launch-proof.txt" <<PROOF
console_window_seconds=12
devicectl_exit_status=$launch_status
bounded_by_watchdog=$([[ -f "$watchdog_marker" ]] && printf 'yes' || printf 'no')
launch_log_preserved=yes
foreground_relaunch=passed
PROOF
}

# XcodeGen rewrites source-group paths for the isolated output directory, but
# string build settings and xcconfig references remain relative to SRCROOT.
# Keep those paths valid without generating into (or mutating) the source tree.
[[ -d "$BUILD_APP_ROOT/Sources" ]] || die "application source directory is missing"
link_project_input "$BUILD_APP_ROOT/Sources" "$PROJECT_DIR/Sources"

for required_config in AppConfig.xcconfig ReleaseConfig.xcconfig; do
    [[ -f "$BUILD_APP_ROOT/$required_config" ]] || {
        die "required build configuration is missing: $BUILD_APP_ROOT/$required_config"
    }
    link_project_input \
        "$BUILD_APP_ROOT/$required_config" "$PROJECT_DIR/$required_config"
done
for optional_config in Secrets.xcconfig PublicConfig.xcconfig; do
    if [[ "$MODE" == "full" ]]; then
        [[ ! -e "$BUILD_APP_ROOT/$optional_config" \
            && ! -L "$BUILD_APP_ROOT/$optional_config" ]] || {
            die "committed release snapshot contains forbidden $optional_config"
        }
    elif [[ -e "$BUILD_APP_ROOT/$optional_config" \
        || -L "$BUILD_APP_ROOT/$optional_config" ]]; then
        [[ -f "$BUILD_APP_ROOT/$optional_config" ]] || {
            die "optional build configuration is not a regular file: $BUILD_APP_ROOT/$optional_config"
        }
        link_project_input \
            "$BUILD_APP_ROOT/$optional_config" "$PROJECT_DIR/$optional_config"
    fi
done

note "Checking source formatting and support artifacts"
git -C "$REPO_ROOT" diff --check

while IFS= read -r -d '' plist_path; do
    plutil -lint "$plist_path"
done < <(
    find "$BUILD_APP_ROOT/Sources" -type f \
        \( -name '*.plist' -o -name '*.entitlements' -o -name '*.xcprivacy' \) \
        -print0
)

while IFS= read -r -d '' json_path; do
    jq empty "$json_path"
done < <(find "$BUILD_APP_ROOT/Sources/Support" -type f -name '*.json' -print0)

assert_equal \
    "$(plistbuddy_value "$BUILD_APP_ROOT/Sources/Support/BiteCast.entitlements" \
        ':com.apple.developer.weatherkit')" \
    "true" \
    "source WeatherKit entitlement"

readonly PHYSICAL_TEST_SOURCE="$BUILD_APP_ROOT/Tests/CatchProtectionDeviceTests.swift"
[[ -f "$PHYSICAL_TEST_SOURCE" ]] || {
    die "physical complete-file-protection test source is missing"
}
rg -q 'func physicalCatchTransactionUsesCompleteFileProtection\(' \
    "$PHYSICAL_TEST_SOURCE" || {
    die "physical complete-file-protection test selector is missing"
}

if find "$BUILD_APP_ROOT/Sources/Support/Assets.xcassets/Species" \
    -type f ! -name 'Contents.json' -print -quit | grep -q .; then
    find "$BUILD_APP_ROOT/Sources/Support/Assets.xcassets/Species" \
        -type f ! -name 'Contents.json' -print >&2
    die "unapproved bundled species media is present"
fi

readonly SECRET_PATTERN='r8_[A-Za-z0-9]{24,}|AIza[0-9A-Za-z_-]{30,}|AKIA[0-9A-Z]{16}|-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----'
readonly FORBIDDEN_CONFIG_ASSIGNMENT_PATTERN='(REPLICATE_API_TOKEN|AMAZON_ACCESS_KEY|AMAZON_SECRET_KEY|EBAY_CLIENT_ID|EBAY_CLIENT_SECRET|YOUTUBE_API_KEY)[[:space:]]*='
assert_rg_no_matches \
    "application source credential scan" \
    "$AUDIT_DIR/source-secret-hits.txt" \
    -l --hidden \
    -g '!BiteCast.xcodeproj/**' \
    -g '!build/**' \
    -g '!Secrets.xcconfig' \
    -g '!Secrets.xcconfig.example' \
    -g '!PublicConfig.xcconfig' \
    -g '!PublicConfig.xcconfig.example' \
    -- "$SECRET_PATTERN" "$BUILD_APP_ROOT"

note "Generating an isolated Xcode project"
run_logged "$LOG_DIR/xcodegen.log" \
    xcodegen generate --no-env \
    --spec "$BUILD_APP_ROOT/project.yml" \
    --project "$PROJECT_DIR" \
    --project-root "$BUILD_APP_ROOT"

[[ -d "$PROJECT" ]] || die "XcodeGen did not create $PROJECT"
[[ -f "$PROJECT_DIR/Sources/Support/Info.plist" ]] || \
    die "isolated project cannot resolve the Release Info.plist"
[[ -f "$PROJECT_DIR/Sources/Support/BiteCast.entitlements" ]] || \
    die "isolated project cannot resolve the signing entitlements"
[[ -f "$PROJECT_DIR/AppConfig.xcconfig" ]] || \
    die "isolated project cannot resolve the Debug xcconfig"
[[ -f "$PROJECT_DIR/ReleaseConfig.xcconfig" ]] || \
    die "isolated project cannot resolve the Release xcconfig"

run_logged "$LOG_DIR/xcode-list.log" \
    xcodebuild -project "$PROJECT" -scheme BiteCast -list

run_logged "$LOG_DIR/release-build-settings.log" \
    xcodebuild -project "$PROJECT" -scheme BiteCast -configuration Release \
    -destination 'generic/platform=iOS' -showBuildSettings

setting_value() {
    local setting_name="$1"
    awk -F ' = ' -v expected="$setting_name" '
        {
            key = $1
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", key)
            if (key == expected) {
                print $2
                exit
            }
        }
    ' "$LOG_DIR/release-build-settings.log"
}

BUILD_NUMBER=""
MARKETING_VERSION=""
BUNDLE_ID=""
if ! BUILD_NUMBER="$(setting_value CURRENT_PROJECT_VERSION)"; then
    die "could not read the Release build number"
fi
if ! MARKETING_VERSION="$(setting_value MARKETING_VERSION)"; then
    die "could not read the Release marketing version"
fi
if ! BUNDLE_ID="$(setting_value PRODUCT_BUNDLE_IDENTIFIER)"; then
    die "could not read the Release bundle identifier"
fi
readonly BUILD_NUMBER MARKETING_VERSION BUNDLE_ID

[[ "$BUILD_NUMBER" =~ ^[0-9]+$ ]] || die "build number is not an integer: $BUILD_NUMBER"
(( 10#$BUILD_NUMBER > 0 )) || die "build number must be a positive integer"
[[ -n "$MARKETING_VERSION" ]] || die "marketing version is empty"
assert_equal "$BUNDLE_ID" "$EXPECTED_BUNDLE_ID" "Release bundle identifier"
assert_equal "$(setting_value DEVELOPMENT_TEAM)" "$EXPECTED_TEAM_ID" "development team"
assert_equal "$(setting_value CODE_SIGN_STYLE)" "Automatic" "code-signing style"
assert_equal "$(setting_value INFOPLIST_FILE)" \
    "Sources/Support/Info.plist" "Release Info.plist"
assert_equal "$(setting_value CODE_SIGN_ENTITLEMENTS)" \
    "Sources/Support/BiteCast.entitlements" "code-signing entitlements file"
assert_equal "$(setting_value IPHONEOS_DEPLOYMENT_TARGET)" "26.5" \
    "deployment target"

if rg -q 'SWIFT_ACTIVE_COMPILATION_CONDITIONS = .*DEBUG' \
    "$LOG_DIR/release-build-settings.log"; then
    die "Release build settings contain the DEBUG compilation condition"
fi

cat > "$RUN_ROOT/preflight-summary.txt" <<SUMMARY
git_sha=$SOURCE_GIT_SHA
mode=$MODE
source_root=$BUILD_APP_ROOT
bundle_id=$BUNDLE_ID
marketing_version=$MARKETING_VERSION
build_number=$BUILD_NUMBER
xcode=$(xcodebuild -version | tr '\n' ' ')
xcodegen=$(xcodegen --version)
SUMMARY

if [[ "$MODE" == "preflight" ]]; then
    printf 'exit_status=0\n' > "$RUN_ROOT/gate-exit-status.txt"
    note "Preflight passed"
    printf 'Evidence: %s\n' "$RUN_ROOT"
    exit 0
fi

SIMULATOR_ID=""
if ! SIMULATOR_ID="$(
    xcrun simctl list devices available -j | jq -r \
        --arg runtime "$REQUIRED_SIMULATOR_RUNTIME" \
        --arg name "$REQUIRED_SIMULATOR_NAME" \
        '(.devices[$runtime] // [])
         | map(select(.name == $name and .isAvailable == true))
         | if length == 1 then .[0].udid else empty end'
)"; then
    die "could not query the required simulator destination"
fi
[[ -n "$SIMULATOR_ID" ]] || {
    die "exactly one available $REQUIRED_SIMULATOR_NAME / iOS 26.5 simulator is required"
}
readonly SIMULATOR_ID
readonly SIMULATOR_DESTINATION="platform=iOS Simulator,id=$SIMULATOR_ID"

if [[ "$(xcrun simctl list devices -j | jq -r \
    --arg runtime "$REQUIRED_SIMULATOR_RUNTIME" \
    --arg id "$SIMULATOR_ID" \
    '.devices[$runtime][] | select(.udid == $id) | .state')" == "Shutdown" ]]; then
    xcrun simctl boot "$SIMULATOR_ID"
fi
xcrun simctl bootstatus "$SIMULATOR_ID" -b

WARNING_SETTINGS=(
    SWIFT_TREAT_WARNINGS_AS_ERRORS=YES
    GCC_TREAT_WARNINGS_AS_ERRORS=YES
)
XCODE_BASE=(xcodebuild -project "$PROJECT" -scheme BiteCast)

note "Running the complete unit and UI suite"
run_logged "$LOG_DIR/full-tests.log" \
    "${XCODE_BASE[@]}" test \
    -destination "$SIMULATOR_DESTINATION" \
    -derivedDataPath "$RUN_ROOT/derived-tests" \
    -resultBundlePath "$RESULT_DIR/full-tests.xcresult" \
    -parallel-testing-enabled NO \
    -enableCodeCoverage YES \
    "${WARNING_SETTINGS[@]}"

xcrun xcresulttool get test-results summary \
    --path "$RESULT_DIR/full-tests.xcresult" \
    > "$RESULT_DIR/full-tests-summary.json"
xcrun xcresulttool export attachments \
    --path "$RESULT_DIR/full-tests.xcresult" \
    --output-path "$RESULT_DIR/screenshots"

note "Building Debug simulator"
run_logged "$LOG_DIR/debug-simulator-build.log" \
    "${XCODE_BASE[@]}" build -configuration Debug \
    -destination "$SIMULATOR_DESTINATION" \
    -derivedDataPath "$RUN_ROOT/derived-debug-simulator" \
    -resultBundlePath "$RESULT_DIR/debug-simulator.xcresult" \
    "${WARNING_SETTINGS[@]}"

note "Building signed Debug device product"
run_xcode_with_optional_provisioning "$LOG_DIR/debug-device-build.log" \
    "${XCODE_BASE[@]}" build -configuration Debug \
    -destination 'generic/platform=iOS' \
    -derivedDataPath "$RUN_ROOT/derived-debug-device" \
    -resultBundlePath "$RESULT_DIR/debug-device.xcresult" \
    "${WARNING_SETTINGS[@]}"

note "Building signed Release device product"
run_xcode_with_optional_provisioning "$LOG_DIR/release-device-build.log" \
    "${XCODE_BASE[@]}" build -configuration Release \
    -destination 'generic/platform=iOS' \
    -derivedDataPath "$RUN_ROOT/derived-release-device" \
    -resultBundlePath "$RESULT_DIR/release-device.xcresult" \
    "${WARNING_SETTINGS[@]}" \
    VALIDATE_PRODUCT=YES

readonly RELEASE_DEVICE_APP="$RUN_ROOT/derived-release-device/Build/Products/Release-iphoneos/BiteCast.app"
[[ -d "$RELEASE_DEVICE_APP" ]] || die "Release device app is missing"

audit_app() {
    local app_path="$1"
    local label="$2"
    local require_distribution="$3"
    local output_dir="$AUDIT_DIR/$label"
    local info_plist="$app_path/Info.plist"
    local executable_name
    local executable_path
    local entitlements_plist="$output_dir/entitlements.plist"
    local profile_plist="$output_dir/profile.plist"
    local profile_app_id
    local profile_expiration
    local profile_expiration_epoch
    local now_epoch

    mkdir -p "$output_dir"
    [[ -f "$info_plist" ]] || die "$label has no Info.plist"
    plutil -lint "$info_plist"

    assert_equal "$(plist_value "$info_plist" CFBundleIdentifier)" \
        "$EXPECTED_BUNDLE_ID" "$label bundle identifier"
    assert_equal "$(plist_value "$info_plist" CFBundleVersion)" \
        "$BUILD_NUMBER" "$label build number"
    assert_equal "$(plist_value "$info_plist" CFBundleShortVersionString)" \
        "$MARKETING_VERSION" "$label marketing version"

    local forbidden_key
    for forbidden_key in ReplicateAPIToken AmazonAccessKey AmazonSecretKey \
        EbayClientID EbayClientSecret YouTubeAPIKey; do
        if plutil -type "$forbidden_key" "$info_plist" >/dev/null 2>&1; then
            die "$label contains forbidden Release Info key: $forbidden_key"
        fi
    done
    if plutil -p "$info_plist" | grep -Fq '$('; then
        die "$label contains an unresolved build-setting sentinel"
    fi

    [[ -f "$app_path/PrivacyInfo.xcprivacy" ]] || {
        die "$label is missing PrivacyInfo.xcprivacy"
    }
    plutil -lint "$app_path/PrivacyInfo.xcprivacy"

    executable_name="$(plist_value "$info_plist" CFBundleExecutable)"
    executable_path="$app_path/$executable_name"
    [[ -x "$executable_path" ]] || die "$label executable is missing"
    LC_ALL=C strings "$executable_path" > "$output_dir/executable.strings.txt"
    assert_rg_no_matches \
        "$label Debug fixture scan" \
        "$output_dir/debug-fixture-hits.txt" \
        -n -- \
        'DebugPreviewHost|Unknown -uiPreview target|app\.choatelabs\.bitecast\.debug\.biteTime' \
        "$output_dir/executable.strings.txt"
    assert_rg_no_matches \
        "$label executable credential scan" \
        "$output_dir/executable-secret-hits.txt" \
        -a -l -- "$SECRET_PATTERN" "$executable_path"
    assert_rg_no_matches \
        "$label application-bundle credential scan" \
        "$output_dir/bundle-secret-hits.txt" \
        -a -l --hidden -- "$SECRET_PATTERN" "$app_path"
    assert_rg_no_matches \
        "$label forbidden configuration assignment scan" \
        "$output_dir/bundle-config-assignment-hits.txt" \
        -a -l --hidden -- "$FORBIDDEN_CONFIG_ASSIGNMENT_PATTERN" "$app_path"
    find "$app_path" -type f \
        \( -name 'Secrets.xcconfig' -o -name 'PublicConfig.xcconfig' \
        -o -name 'AppConfig.xcconfig' -o -name 'ReleaseConfig.xcconfig' \
        -o -name '.env' -o -name '*.p8' -o -name '*.p12' \) \
        -print > "$output_dir/forbidden-config-files.txt"
    if [[ -s "$output_dir/forbidden-config-files.txt" ]]; then
        cat "$output_dir/forbidden-config-files.txt" >&2
        die "$label contains a forbidden configuration or credential file"
    fi

    codesign --verify --deep --strict --verbose=2 "$app_path"
    codesign -dv --verbose=4 "$app_path" > /dev/null \
        2> "$output_dir/signature.txt"
    codesign -d --entitlements :- "$app_path" \
        > "$entitlements_plist" 2> "$output_dir/entitlements.log"
    plutil -lint "$entitlements_plist"
    assert_equal "$(plistbuddy_value "$entitlements_plist" \
        ':com.apple.developer.weatherkit')" "true" \
        "$label signed WeatherKit entitlement"

    [[ -f "$app_path/embedded.mobileprovision" ]] || {
        die "$label is missing embedded.mobileprovision"
    }
    security cms -D -i "$app_path/embedded.mobileprovision" \
        > "$profile_plist"
    plutil -lint "$profile_plist"
    profile_expiration="$(plist_value "$profile_plist" ExpirationDate)"
    if ! profile_expiration_epoch="$(date -j -u \
        -f '%Y-%m-%dT%H:%M:%SZ' "$profile_expiration" '+%s' 2>/dev/null)"; then
        die "$label profile has an unreadable ExpirationDate: $profile_expiration"
    fi
    now_epoch="$(date -u '+%s')"
    (( profile_expiration_epoch > now_epoch )) || {
        die "$label provisioning profile expired at $profile_expiration"
    }
    printf '%s\n' "$profile_expiration" > "$output_dir/profile-expiration.txt"
    assert_equal "$(plistbuddy_value "$profile_plist" \
        ':Entitlements:com.apple.developer.weatherkit')" "true" \
        "$label profile WeatherKit entitlement"
    profile_app_id="$(plistbuddy_value "$profile_plist" \
        ':Entitlements:application-identifier')"
    assert_equal "$profile_app_id" \
        "$EXPECTED_TEAM_ID.$EXPECTED_BUNDLE_ID" \
        "$label profile application identifier"

    if [[ "$require_distribution" -eq 1 ]]; then
        rg -q '^Authority=Apple Distribution:' "$output_dir/signature.txt" || {
            die "$label is not signed with Apple Distribution"
        }
        if [[ "$(plistbuddy_value "$entitlements_plist" ':get-task-allow' \
            2>/dev/null || printf 'false')" == "true" ]]; then
            die "$label distribution entitlements enable get-task-allow"
        fi
        if /usr/libexec/PlistBuddy -c 'Print :ProvisionedDevices' \
            "$profile_plist" >/dev/null 2>&1; then
            die "$label App Store profile unexpectedly contains device identifiers"
        fi
    fi
}

note "Auditing the signed Release device product"
audit_app "$RELEASE_DEVICE_APP" "release-device" 0

note "Creating a Release archive"
readonly ARCHIVE_PATH="$RUN_ROOT/archive/BiteCast.xcarchive"
run_xcode_with_optional_provisioning "$LOG_DIR/archive.log" \
    "${XCODE_BASE[@]}" archive -configuration Release \
    -destination 'generic/platform=iOS' \
    -derivedDataPath "$RUN_ROOT/derived-archive" \
    -archivePath "$ARCHIVE_PATH" \
    -resultBundlePath "$RESULT_DIR/archive.xcresult" \
    "${WARNING_SETTINGS[@]}" \
    VALIDATE_PRODUCT=YES

readonly ARCHIVE_APP="$ARCHIVE_PATH/Products/Applications/BiteCast.app"
[[ -d "$ARCHIVE_APP" ]] || die "archive does not contain BiteCast.app"
audit_app "$ARCHIVE_APP" "archive" 0

readonly ARCHIVE_DSYM="$ARCHIVE_PATH/dSYMs/BiteCast.app.dSYM"
[[ -d "$ARCHIVE_DSYM" ]] || die "archive is missing BiteCast.app.dSYM"
xcrun dwarfdump --uuid "$ARCHIVE_APP/BiteCast" \
    > "$AUDIT_DIR/archive-binary-uuids.txt"
xcrun dwarfdump --uuid "$ARCHIVE_DSYM" \
    > "$AUDIT_DIR/archive-dsym-uuids.txt"
rg -q '^UUID: [0-9A-F-]+ ' "$AUDIT_DIR/archive-binary-uuids.txt" || \
    die "archive executable reported no UUID"
rg -q '^UUID: [0-9A-F-]+ ' "$AUDIT_DIR/archive-dsym-uuids.txt" || \
    die "archive dSYM reported no UUID"
diff -u \
    <(awk '/^UUID:/ { print $2 }' "$AUDIT_DIR/archive-binary-uuids.txt" | sort) \
    <(awk '/^UUID:/ { print $2 }' "$AUDIT_DIR/archive-dsym-uuids.txt" | sort) \
    > "$AUDIT_DIR/archive-uuid-diff.txt" || {
    die "archive binary and dSYM UUIDs do not match"
}

if [[ "$RUN_EXPORT" -eq 1 ]]; then
    note "Attempting local App Store Connect export"
    readonly EXPORT_OPTIONS="$RUN_ROOT/export-options-app-store-connect.plist"
    readonly EXPORT_DIR="$RUN_ROOT/export"
    plutil -create xml1 "$EXPORT_OPTIONS"
    plutil -insert method -string app-store-connect "$EXPORT_OPTIONS"
    plutil -insert destination -string export "$EXPORT_OPTIONS"
    plutil -insert signingStyle -string automatic "$EXPORT_OPTIONS"
    plutil -insert teamID -string "$EXPECTED_TEAM_ID" "$EXPORT_OPTIONS"
    plutil -insert manageAppVersionAndBuildNumber -bool false "$EXPORT_OPTIONS"
    plutil -insert uploadSymbols -bool true "$EXPORT_OPTIONS"
    plutil -insert stripSwiftSymbols -bool true "$EXPORT_OPTIONS"
    plutil -lint "$EXPORT_OPTIONS"
    mkdir -p "$EXPORT_DIR"

    run_xcode_with_optional_provisioning "$LOG_DIR/export.log" \
        xcodebuild -exportArchive \
        -archivePath "$ARCHIVE_PATH" \
        -exportPath "$EXPORT_DIR" \
        -exportOptionsPlist "$EXPORT_OPTIONS"

    IPA_PATH=""
    if ! IPA_PATH="$(find "$EXPORT_DIR" -maxdepth 1 \
        -type f -name '*.ipa' -print -quit)"; then
        die "could not inspect the App Store export directory"
    fi
    [[ -n "$IPA_PATH" ]] || die "App Store Connect export produced no IPA"
    readonly IPA_PATH
    shasum -a 256 "$IPA_PATH" > "$AUDIT_DIR/exported-ipa.sha256"

    readonly UNPACK_DIR="$RUN_ROOT/export-unpacked"
    mkdir -p "$UNPACK_DIR"
    /usr/bin/ditto -x -k "$IPA_PATH" "$UNPACK_DIR"
    EXPORTED_APP=""
    if ! EXPORTED_APP="$(find "$UNPACK_DIR/Payload" -maxdepth 1 \
        -type d -name '*.app' -print -quit)"; then
        die "could not inspect the unpacked App Store export"
    fi
    [[ -n "$EXPORTED_APP" ]] || die "exported IPA contains no application"
    readonly EXPORTED_APP
    audit_app "$EXPORTED_APP" "app-store-export" 1
fi

DEVICE_INSTALL_MODE="not-attempted"
DEVICE_FIRST_INSTALL_STATUS="not-attempted"
DEVICE_REINSTALL_STATUS="not-attempted"
DEVICE_CONTAINER_STATUS="not-attempted"
DEVICE_PREFERENCES_STATUS="not-attempted"
PHYSICAL_PROTECTION_STATUS="not-attempted"
DEVICE_LAUNCH_STATUS="not-attempted"
DEVICE_SCREENSHOT_STATUS="not-attempted"

if [[ -n "$DEVICE_ID" ]]; then
    note "Performing guarded physical-device release proof"
    readonly DEVICE_DETAILS_JSON="$AUDIT_DIR/device-details.json"
    readonly BEFORE_APPS_JSON="$AUDIT_DIR/device-app-before.json"
    readonly AFTER_FIRST_APPS_JSON="$AUDIT_DIR/device-app-after-first-install.json"
    readonly AFTER_REINSTALL_APPS_JSON="$AUDIT_DIR/device-app-after-reinstall.json"
    readonly FIRST_INSTALL_JSON="$AUDIT_DIR/device-first-release-install.json"
    readonly REINSTALL_JSON="$AUDIT_DIR/device-release-reinstall.json"
    readonly PREFERENCES_BEFORE="$AUDIT_DIR/device-preferences-before.txt"
    readonly PREFERENCES_AFTER_FIRST="$AUDIT_DIR/device-preferences-after-first-install.txt"
    readonly PREFERENCES_AFTER_REINSTALL="$AUDIT_DIR/device-preferences-after-reinstall.txt"

    run_logged "$LOG_DIR/device-details.log" \
        xcrun devicectl device info details \
        --device "$DEVICE_ID" \
        --json-output "$DEVICE_DETAILS_JSON" \
        --log-output "$LOG_DIR/device-details-devicectl.log" \
        --timeout 30
    jq empty "$DEVICE_DETAILS_JSON" || die "physical-device details JSON is malformed"
    PHYSICAL_DEVICE_UDID=""
    if ! PHYSICAL_DEVICE_UDID="$(jq -r \
        '.result.hardwareProperties.udid // empty' "$DEVICE_DETAILS_JSON")"; then
        die "could not read the physical-device UDID"
    fi
    readonly PHYSICAL_DEVICE_UDID
    assert_equal "$PHYSICAL_DEVICE_UDID" "$PHYSICAL_XCODE_DESTINATION_ID" \
        "physical-device Xcode destination identifier"

    capture_device_app_state "$BEFORE_APPS_JSON" "before"
    OLD_BUILD=""
    OLD_CONTAINER=""
    if ! OLD_BUILD="$(jq -r \
        '.result.apps[0].bundleVersion' "$BEFORE_APPS_JSON")"; then
        die "could not read the installed build number"
    fi
    if ! OLD_CONTAINER="$(jq -r \
        '.result.apps[0].dataContainerPath' "$BEFORE_APPS_JSON")"; then
        die "could not read the installed data-container path"
    fi
    readonly OLD_BUILD OLD_CONTAINER
    if ! DEVICE_INSTALL_MODE="$(classify_install_build "$BUILD_NUMBER" "$OLD_BUILD")"; then
        die "candidate or installed build number is invalid"
    fi
    case "$DEVICE_INSTALL_MODE" in
        downgrade)
            die "refusing to downgrade installed build $OLD_BUILD to $BUILD_NUMBER"
            ;;
        idempotent-reinstall)
            note "Installed build equals candidate; proving an idempotent reinstall"
            ;;
        upgrade)
            note "Candidate build $BUILD_NUMBER upgrades installed build $OLD_BUILD"
            ;;
        *) die "unexpected device-install classification: $DEVICE_INSTALL_MODE" ;;
    esac
    printf 'candidate_build=%s\ninstalled_build=%s\nmode=%s\n' \
        "$BUILD_NUMBER" "$OLD_BUILD" "$DEVICE_INSTALL_MODE" \
        > "$AUDIT_DIR/device-install-classification.txt"

    capture_preferences_fingerprint "before" "$PREFERENCES_BEFORE"

    note "Installing the first signed Release product without removing app data"
    assert_live_source_unchanged "first physical Release install"
    run_logged "$LOG_DIR/device-first-release-install.log" \
        xcrun devicectl device install app \
        --device "$DEVICE_ID" \
        --json-output "$FIRST_INSTALL_JSON" \
        --log-output "$LOG_DIR/device-first-release-install-devicectl.log" \
        --timeout 120 \
        "$RELEASE_DEVICE_APP"
    DEVICE_FIRST_INSTALL_STATUS="passed"

    capture_device_app_state "$AFTER_FIRST_APPS_JSON" "after-first-install"
    assert_equal "$(jq -r '.result.apps[0].bundleVersion' "$AFTER_FIRST_APPS_JSON")" \
        "$BUILD_NUMBER" "first-install build number"
    assert_equal "$(jq -r '.result.apps[0].dataContainerPath' "$AFTER_FIRST_APPS_JSON")" \
        "$OLD_CONTAINER" "first-install preserved data-container path"
    capture_preferences_fingerprint "after-first-install" "$PREFERENCES_AFTER_FIRST"
    assert_preferences_unchanged \
        "$PREFERENCES_BEFORE" "$PREFERENCES_AFTER_FIRST" "after-first-install"

    note "Running the exact physical complete-file-protection test"
    assert_live_source_unchanged "physical complete-file-protection test"
    run_xcode_with_optional_provisioning "$LOG_DIR/physical-catch-protection-test.log" \
        "${XCODE_BASE[@]}" test -configuration Debug \
        -destination "platform=iOS,id=$PHYSICAL_XCODE_DESTINATION_ID" \
        -derivedDataPath "$RUN_ROOT/derived-physical-catch-protection" \
        -resultBundlePath "$RESULT_DIR/physical-catch-protection.xcresult" \
        "-only-testing:$PHYSICAL_PROTECTION_TEST_SELECTOR" \
        -parallel-testing-enabled NO \
        "${WARNING_SETTINGS[@]}"
    xcrun xcresulttool get test-results summary \
        --path "$RESULT_DIR/physical-catch-protection.xcresult" \
        > "$RESULT_DIR/physical-catch-protection-summary.json"
    xcrun xcresulttool get test-results tests \
        --path "$RESULT_DIR/physical-catch-protection.xcresult" \
        > "$RESULT_DIR/physical-catch-protection-tests.json"
    assert_physical_test_result \
        "$RESULT_DIR/physical-catch-protection-summary.json" \
        "$RESULT_DIR/physical-catch-protection-tests.json"
    PHYSICAL_PROTECTION_STATUS="passed"

    note "Reinstalling the signed Release product after the physical test"
    assert_live_source_unchanged "second physical Release install"
    run_logged "$LOG_DIR/device-release-reinstall.log" \
        xcrun devicectl device install app \
        --device "$DEVICE_ID" \
        --json-output "$REINSTALL_JSON" \
        --log-output "$LOG_DIR/device-release-reinstall-devicectl.log" \
        --timeout 120 \
        "$RELEASE_DEVICE_APP"
    DEVICE_REINSTALL_STATUS="passed"

    capture_device_app_state "$AFTER_REINSTALL_APPS_JSON" "after-reinstall"
    assert_equal "$(jq -r '.result.apps[0].bundleVersion' "$AFTER_REINSTALL_APPS_JSON")" \
        "$BUILD_NUMBER" "reinstall build number"
    assert_equal "$(jq -r '.result.apps[0].dataContainerPath' "$AFTER_REINSTALL_APPS_JSON")" \
        "$OLD_CONTAINER" "reinstall preserved data-container path"
    DEVICE_CONTAINER_STATUS="passed"
    capture_preferences_fingerprint "after-reinstall" "$PREFERENCES_AFTER_REINSTALL"
    assert_preferences_unchanged \
        "$PREFERENCES_BEFORE" "$PREFERENCES_AFTER_REINSTALL" "after-reinstall"
    DEVICE_PREFERENCES_STATUS="passed"

    note "Launching BiteCast with a bounded physical-device console capture"
    launch_device_with_bounded_console
    DEVICE_LAUNCH_STATUS="passed"

    run_logged "$AUDIT_DIR/device-screenshot-help.txt" \
        xcrun devicectl device capture screenshot --help
    note "Capturing the launched physical-device screen"
    sleep 2
    assert_live_source_unchanged "physical-device screenshot"
    run_logged "$LOG_DIR/device-screenshot.log" \
        xcrun devicectl device capture screenshot \
        --device "$DEVICE_ID" \
        --destination "$AUDIT_DIR/device-screenshot.png" \
        --json-output "$AUDIT_DIR/device-screenshot.json" \
        --log-output "$LOG_DIR/device-screenshot-devicectl.log" \
        --timeout 30
    [[ -s "$AUDIT_DIR/device-screenshot.png" ]] || {
        die "physical-device screenshot is empty"
    }
    DEVICE_SCREENSHOT_STATUS="passed"
fi

assert_live_source_unchanged "final release-gate success"
cat > "$RUN_ROOT/gate-status.txt" <<STATUS
source_git_sha=$SOURCE_GIT_SHA
source_snapshot=passed
source_archive_sha256=$(awk '{ print $1 }' "$AUDIT_DIR/source-head.tar.sha256")
physical_xcode_destination_id=$PHYSICAL_XCODE_DESTINATION_ID
bundle_id=$BUNDLE_ID
marketing_version=$MARKETING_VERSION
build_number=$BUILD_NUMBER
tests=passed
debug_simulator_build=passed
debug_device_build=passed
release_device_build=passed
archive=passed
app_store_export=$([[ "$RUN_EXPORT" -eq 1 ]] && printf 'passed' || printf 'not-attempted')
device_install_mode=$DEVICE_INSTALL_MODE
device_first_release_install=$DEVICE_FIRST_INSTALL_STATUS
physical_catch_protection_test=$PHYSICAL_PROTECTION_STATUS
device_release_reinstall=$DEVICE_REINSTALL_STATUS
device_container_preservation=$DEVICE_CONTAINER_STATUS
device_preferences_preservation=$DEVICE_PREFERENCES_STATUS
device_launch_console_log=$DEVICE_LAUNCH_STATUS
device_screenshot=$DEVICE_SCREENSHOT_STATUS
STATUS

printf 'exit_status=0\n' > "$RUN_ROOT/gate-exit-status.txt"
note "Local release gate passed"
if [[ "$RUN_EXPORT" -ne 1 ]]; then
    printf 'NOTICE: App Store Connect export was not attempted.\n'
fi
if [[ -z "$DEVICE_ID" ]]; then
    printf 'NOTICE: Physical-device release proof was not attempted.\n'
fi
printf 'Evidence: %s\n' "$RUN_ROOT"
