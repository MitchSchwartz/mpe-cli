# Fixed unittest suite registry — enum names only (no passthrough args).
#
# Every module in the product repo's tests/ must appear in at least one suite.
# `mpe test coverage` enforces that; see lib/test_coverage.sh.
#
# Suites may legitimately list modules that are absent from the current
# checkout: the product repo carries feature work on unmerged branches (the
# looper and APC modules live on yolo/looper-phase0, not dev). Suite expansion
# is therefore filtered against tests/ at run time — see
# mpe_cli_test_unittest_cmd. A suite that expands to nothing is an error, never
# a vacuous pass.

MPE_TEST_SUITE_NAMES=(
    all
    apc
    control-surfaces
    looper
    midi
    touch
    audio
    surge
    patch
    calibration
    system
)

mpe_cli_test_suite_is_valid() {
    local name="$1"
    local entry
    for entry in "${MPE_TEST_SUITE_NAMES[@]}"; do
        if [ "$entry" = "$name" ]; then
            return 0
        fi
    done
    return 1
}

# Print unittest module args for a suite name (discover uses empty output + flag).
mpe_cli_test_suite_modules() {
    local name="$1"
    case "$name" in
        all) ;;
        apc | control-surfaces)
            # control-surfaces is an alias of apc. Kept as one list so the two
            # names cannot drift apart the way two hand-typed lists did.
            printf '%s\n' \
                tests.test_apc_mini \
                tests.test_apc_led \
                tests.test_apc_session_midi \
                tests.test_control_surfaces
            ;;
        looper)
            # test_apc_led is cross-listed with apc: LED feedback is driven by
            # looper state, so it belongs to both.
            printf '%s\n' \
                tests.test_looper_engine \
                tests.test_looper_devices \
                tests.test_looper_xruns \
                tests.test_looper_session \
                tests.test_looper_period_debug \
                tests.test_looper_alsa_stderr \
                tests.test_looper_bar_clock \
                tests.test_looper_health \
                tests.test_looper_hud \
                tests.test_looper_timing_publisher \
                tests.test_looper_timing_state \
                tests.test_clip_matrix \
                tests.test_apc_led
            ;;
        midi)
            printf '%s\n' \
                tests.test_midi_sync \
                tests.test_midi_sync_settings \
                tests.test_midi_clock \
                tests.test_calibrate_midi
            ;;
        touch)
            printf '%s\n' \
                tests.test_touch_browser_smoke \
                tests.test_touch_press \
                tests.test_touch_browser_nav_transitions \
                tests.test_touch_browser_nested_nav \
                tests.test_touch_browser_long_press \
                tests.test_touch_browser_normalization_toggle \
                tests.test_touch_browser_patch_reload \
                tests.test_touch_audio_profile_async \
                tests.test_touch_audio_profile_timeout \
                tests.test_touch_calibration \
                tests.test_context_menu \
                tests.test_scrollable_action_list \
                tests.test_content_scroll_hints \
                tests.test_mixer_controls \
                tests.test_ui_text_settings_detail \
                tests.test_ui_theme
            ;;
        audio)
            printf '%s\n' \
                tests.test_audio_engine \
                tests.test_audio_profile \
                tests.test_audio_profile_persist \
                tests.test_detect_audio_device \
                tests.test_usb_audio_recovery \
                tests.test_uac2_card \
                tests.test_uac2_stall_watchdog \
                tests.test_start_uac2_watchdog \
                tests.test_session_capture \
                tests.test_screen_recorder \
                tests.test_surge_audio \
                tests.test_cpu_governor
            ;;
        surge)
            printf '%s\n' \
                tests.test_surge_audio \
                tests.test_surge_playback \
                tests.test_surge_poly_governor
            ;;
        patch)
            printf '%s\n' \
                tests.test_patch_scanner \
                tests.test_patch_scanner_metadata \
                tests.test_patch_metadata \
                tests.test_patch_identity \
                tests.test_patch_normalization \
                tests.test_patch_loader_playback \
                tests.test_patch_pressure \
                tests.test_patch_hold \
                tests.test_patch_sidecar_migration \
                tests.test_norm_dual_anchor \
                tests.test_instrument_filter \
                tests.test_all_patches_index \
                tests.test_favorites_index \
                tests.test_favorites_backup \
                tests.test_migrate_favorites_v2 \
                tests.test_json_store
            ;;
        calibration)
            printf '%s\n' \
                tests.test_calibration_integrity \
                tests.test_calibration_handoff \
                tests.test_calibration_standalone \
                tests.test_calibration_routing \
                tests.test_calibration_progressive_gesture \
                tests.test_calibration_loopback \
                tests.test_calibration_loader_messages \
                tests.test_calibrate_midi
            ;;
        system)
            # Appliance lifecycle: power/shutdown path, splash, networking.
            printf '%s\n' \
                tests.test_shutdown_measure \
                tests.test_dsi_splash_shutdown \
                tests.test_wifi_manager
            ;;
        *)
            echo "$MPE_CLI_NAME test: unknown suite: $name" >&2
            echo "Run '$MPE_CLI_NAME test list' for suite names." >&2
            return 1
            ;;
    esac
}

# Every module named by any suite, deduplicated. Used by the coverage guard.
mpe_cli_test_all_registered_modules() {
    local name
    for name in "${MPE_TEST_SUITE_NAMES[@]}"; do
        [ "$name" = all ] && continue
        mpe_cli_test_suite_modules "$name"
    done | sed 's/^tests\.//' | sort -u
}

mpe_cli_test_suite_list() {
    local name
    for name in "${MPE_TEST_SUITE_NAMES[@]}"; do
        echo "$name"
    done
}

# Build fixed unittest command for repo cwd (no user injection).
#
# Module names come from the registry above, never from argv; the suite name is
# validated against MPE_TEST_SUITE_NAMES before it reaches here. The emitted
# script filters the list against tests/ in the working directory so the same
# command is correct on a laptop clone and on the appliance, whatever branch
# each is on.
mpe_cli_test_unittest_cmd() {
    local suite="$1"
    local modules
    modules="$(mpe_cli_test_suite_modules "$suite")" || return 1

    if [ "$suite" = all ]; then
        printf '%s' 'python3 -m unittest discover -s tests -q'
        return 0
    fi

    cat <<EOF
_mpe_mods=""
_mpe_skipped=""
for _mpe_m in $(echo "$modules" | tr '\n' ' '); do
    if [ -f "tests/\${_mpe_m#tests.}.py" ]; then
        _mpe_mods="\$_mpe_mods \$_mpe_m"
    else
        _mpe_skipped="\$_mpe_skipped \${_mpe_m#tests.}"
    fi
done
if [ -n "\$_mpe_skipped" ]; then
    echo "note: suite '$suite' lists modules absent from this checkout:\$_mpe_skipped" >&2
fi
if [ -z "\$_mpe_mods" ]; then
    echo "error: suite '$suite' matched no test modules in this checkout" >&2
    exit 1
fi
# shellcheck disable=SC2086
python3 -m unittest \$_mpe_mods -q
EOF
}
