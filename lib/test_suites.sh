# Fixed unittest suite registry — enum names only (no passthrough args).

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
        apc) printf '%s\n' tests.test_apc_mini tests.test_control_surfaces ;;
        control-surfaces) printf '%s\n' tests.test_control_surfaces tests.test_apc_mini ;;
        looper)
            printf '%s\n' \
                tests.test_looper_engine \
                tests.test_looper_devices \
                tests.test_looper_xruns
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
                tests.test_ui_text_settings_detail \
                tests.test_ui_theme
            ;;
        audio)
            printf '%s\n' \
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
        *)
            echo "$MPE_CLI_NAME test: unknown suite: $name" >&2
            echo "Run '$MPE_CLI_NAME test list' for suite names." >&2
            return 1
            ;;
    esac
}

mpe_cli_test_suite_list() {
    local name
    for name in "${MPE_TEST_SUITE_NAMES[@]}"; do
        echo "$name"
    done
}

# Build fixed unittest command for repo cwd (no user injection).
mpe_cli_test_unittest_cmd() {
    local suite="$1"
    local modules
    modules="$(mpe_cli_test_suite_modules "$suite")" || return 1
    if [ "$suite" = all ]; then
        printf '%s' 'python3 -m unittest discover -s tests -q'
    else
        # shellcheck disable=SC2086
        printf 'python3 -m unittest %s -q' "$(echo "$modules" | tr '\n' ' ' | sed 's/ $//')"
    fi
}
