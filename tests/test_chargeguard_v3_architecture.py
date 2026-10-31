"""ChargeGuard v3.0 architecture invariants (Linux-verifiable, no Xcode / device needed).

v3.0 is a layered rebuild, not a token tweak:
- layers: CGConfig (model) -> CGDaemonClient (API layer, wraps CLAPIClient)
  -> CGBatteryViewModel (view model) -> CGViews / CGMainViewController (views).
  Views never talk to the daemon directly; read-only features never write.
- main page: gradient hero + 2-column stat grid + 2-column More Functions
  grid (not the old single-column list cards).
- ID rename: com.chargeguard everywhere user-visible; the old id survives
  only in deb Conflicts/Replaces and in the postinst data migration.
- deb Settings-only: no .app in deb stages; daemon in /usr/libexec,
  Settings bundle in PreferenceBundles; the .app stays only in the tipa.
- SwiftUI is deliberately deferred (see REPORT_V3_0.md): no SwiftUI import
  in any new file, because a SwiftUI migration cannot be build-verified
  on Linux without Xcode.
"""
import difflib
import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
CG = ROOT / "ChargeLimiter" / "UIKit" / "ChargeGuard"
PBX = ROOT / "ChargeGuard.xcodeproj" / "project.pbxproj"
BUILD = ROOT / "scripts" / "build_packages.sh"
WORKFLOW = ROOT / ".github" / "workflows" / "release.yml"


def src(name):
    return (CG / name).read_text(encoding="utf-8")


class V3LayerTests(unittest.TestCase):
    def test_new_layers_exist(self):
        for name in ["CGConfig.h", "CGConfig.m", "CGDaemonClient.h", "CGDaemonClient.m",
                     "CGBatteryViewModel.h", "CGBatteryViewModel.m",
                     "CGHistoryAnalytics.h", "CGHistoryAnalytics.m",
                     "CGPresetManager.h", "CGPresetManager.m",
                     "CGDiagnosticsExporter.h", "CGDiagnosticsExporter.m",
                     "CGViews.h", "CGViews.m",
                     "CGMainViewController.h", "CGMainViewController.m",
                     "CGSubPages.h", "CGSubPages.m"]:
            self.assertTrue((CG / name).exists(), f"missing {name}")

    def test_views_never_talk_to_daemon_directly(self):
        views = src("CGViews.m")
        self.assertNotIn("CLAPIClient", views)
        self.assertNotIn("CGDaemonClient", views)
        self.assertNotIn("127.0.0.1", views)
        main = src("CGMainViewController.m")
        self.assertNotIn("CLAPIClient", main)
        self.assertIn("CGDaemonClient", main)
        # View model is pure: no UIKit, no daemon.
        vm = src("CGBatteryViewModel.m")
        self.assertNotIn("CLAPIClient", vm)
        self.assertNotIn("#import <UIKit", src("CGBatteryViewModel.h"))

    def test_config_defaults_and_ranges_unchanged(self):
        config = src("CGConfig.m")
        self.assertIn("config.stopChargeAbove = 80;", config)
        self.assertIn("config.startChargeBelow = 20;", config)
        self.assertIn("config.tempAbove = 40;", config)
        self.assertIn("config.tempBelow = 35;", config)
        self.assertIn("stopChargeAbove < 15 || self.stopChargeAbove > 100", config)
        self.assertIn("tempAbove < 30 || self.tempAbove > 50", config)

    def test_daemon_client_is_the_only_write_gate(self):
        client = src("CGDaemonClient.m")
        self.assertIn("isValidWithError", client)
        self.assertIn("setConfigWithKey", client)
        # Read-only features never import the client or the transport.
        self.assertNotIn("CGDaemonClient", src("CGHistoryAnalytics.m"))
        self.assertNotIn("CLAPIClient", src("CGHistoryAnalytics.m"))
        self.assertNotIn("CGDaemonClient", src("CGDiagnosticsExporter.m"))
        self.assertNotIn("CLAPIClient", src("CGDiagnosticsExporter.m"))
        self.assertNotIn("CLAPIClient", src("CGPresetManager.m"))

    def test_no_swiftui_claim(self):
        for name in ["CGMainViewController.m", "CGViews.m", "CGSubPages.m"]:
            self.assertNotIn("SwiftUI", src(name), name)

    def test_pbxproj_includes_new_sources(self):
        pbx = PBX.read_text(encoding="utf-8")
        for name in ["CGConfig.m", "CGDaemonClient.m", "CGBatteryViewModel.m",
                     "CGHistoryAnalytics.m", "CGPresetManager.m",
                     "CGDiagnosticsExporter.m", "CGViews.m",
                     "CGMainViewController.m", "CGSubPages.m"]:
            self.assertIn(f"{name} in Sources", pbx, name)


class V3MainPageTests(unittest.TestCase):
    def test_more_functions_is_2_column_grid(self):
        main = src("CGMainViewController.m")
        self.assertIn("CGEntryGridView", main)
        self.assertIn("更多功能", main)
        entries = src("CGViews.m")
        # Grid rows advance by 2 and distribute equally: 2 columns, not a list.
        self.assertIn("rowStart += 2", entries)
        self.assertIn("UIStackViewDistributionFillEqually", entries)
        # All four More Functions entries exist in the new main page.
        for title in ["历史统计", "电池兼容性测试", "充电高级", "软件设置"]:
            self.assertIn(title, main, title)

    def test_stat_grid_is_2_column(self):
        views = src("CGViews.m")
        self.assertIn("CGStatGridView", views)
        vm = src("CGBatteryViewModel.m")
        for title in ["电流", "电压", "温度", "健康度"]:
            self.assertIn(title, vm, title)

    def test_hero_has_pills(self):
        self.assertIn("modePillText", src("CGViews.m"))
        self.assertIn("adapterPillText", src("CGViews.m"))
        self.assertIn("CAGradientLayer", src("CGViews.m"))

    def test_no_function_deleted_in_new_main(self):
        # New pages route to legacy full pages; the legacy controllers
        # are still referenced, not removed.
        main = src("CGMainViewController.m")
        sub = src("CGSubPages.m")
        for legacy in ["CLHistoryViewController", "CLAdvancedSettingsViewController",
                       "CLBatteryCompatibilityTestViewController",
                       "CLSoftwareSettingsViewController", "CLHelpViewController"]:
            self.assertTrue(legacy in main or legacy in sub, legacy)


class V3IdAndPackagingTests(unittest.TestCase):
    def test_old_package_id_gone_from_user_visible_packaging(self):
        pbx = PBX.read_text(encoding="utf-8")
        self.assertNotIn("com.chargelimiter.mod", pbx)
        build = BUILD.read_text(encoding="utf-8")
        self.assertNotIn("com.chargelimiter.mod", build)
        workflow = WORKFLOW.read_text(encoding="utf-8")
        # The workflow may mention the old id only in the Conflicts/Replaces check.
        self.assertEqual(workflow.count("com.chargelimiter.mod"), 2)
        self.assertIn("Conflicts: com.chargelimiter.mod", workflow)
        self.assertIn("Replaces: com.chargelimiter.mod", workflow)
        for control in [ROOT / "ChargeLimiter" / "Package" / "DEBIAN" / "control",
                        ROOT / "ChargeLimiter" / "Package_rootless" / "DEBIAN" / "control",
                        ROOT / "ChargeLimiter" / "Package_roothide" / "DEBIAN" / "control"]:
            text = control.read_text(encoding="utf-8")
            self.assertIn("Package: com.chargeguard", text)
            self.assertIn("Conflicts: com.chargelimiter.mod", text)
            self.assertIn("Replaces: com.chargelimiter.mod", text)
            self.assertIn("Version: 3.0", text)

    def test_deb_staging_has_no_app_and_has_daemon_plus_bundle(self):
        build = BUILD.read_text(encoding="utf-8")
        self.assertIn("usr/libexec/ChargeGuardDaemon", build)
        self.assertIn("PreferenceBundles", build)
        self.assertIn("must not contain Applications", build)
        # No .app is copied into any deb stage; the only .app copy is the tipa.
        self.assertNotIn('cp -a "$ROOTFUL_APP" "$STAGE_ROOTFUL_DIR', build)
        self.assertNotIn('cp -a "$ROOTLESS_APP" "$STAGE_ROOTLESS_DIR', build)
        self.assertNotIn('cp -a "$ROOTHIDE_APP" "$STAGE_ROOTHIDE_DIR', build)
        self.assertIn('cp -a "$ROOTLESS_APP" "$PAYLOAD_DIR/ChargeGuard.app"', build)

    def test_postinst_migration_keeps_old_dir(self):
        for postinst in [ROOT / "ChargeLimiter" / "Package" / "DEBIAN" / "postinst",
                         ROOT / "ChargeLimiter" / "Package_rootless" / "DEBIAN" / "postinst",
                         ROOT / "ChargeLimiter" / "Package_roothide" / "DEBIAN" / "postinst"]:
            text = postinst.read_text(encoding="utf-8")
            self.assertIn('/var/mobile/ChargeLimiter', text)
            self.assertIn('/var/mobile/ChargeGuard', text)
            self.assertIn('cp -a "$OLD_DATA_DIR"/. "$NEW_DATA_DIR"/', text)
            # Migration must never delete the old dir.
            self.assertNotIn('rm -rf "$OLD_DATA_DIR"', text)
            self.assertNotIn('rm -rf $OLD_DATA_DIR', text)

    def test_daemon_diff_vs_audit_is_identifier_only(self):
        audit = ROOT.parent / "charge-limiter-audit" / "ChargeLimiter" / "daemon.mm"
        if not audit.exists():
            self.skipTest("audit copy not present")
        work = (ROOT / "ChargeLimiter" / "daemon.mm").read_text(encoding="utf-8").splitlines()
        orig = audit.read_text(encoding="utf-8").splitlines()
        minus = []
        plus = []
        for line in difflib.unified_diff(orig, work, lineterm=""):
            if line.startswith("-") and not line.startswith("---"):
                minus.append(line[1:])
            elif line.startswith("+") and not line.startswith("+++"):
                plus.append(line[1:])
        self.assertTrue(plus, "expected at least the binary-name rename in daemon.mm")
        # Each removed line, with only identifier renames applied, must
        # reappear as an added line: no logic change, only names/paths.
        for old_line in minus:
            renamed = (old_line.replace("com.chargelimiter.mod", "com.chargeguard")
                               .replace("ChargeLimiter", "ChargeGuard")
                               .replace("chargelimiter", "chargeguard"))
            self.assertIn(renamed, plus, f"daemon.mm change is not identifier-only: {old_line}")


class V3OvernightApplyTests(unittest.TestCase):
    def test_daemon_dictionary_includes_use_smart(self):
        cfg = (ROOT / "ChargeLimiter" / "UIKit" / "ChargeGuard" / "CGConfig.m").read_text(encoding="utf-8")
        self.assertIn('@\"use_smart\"', cfg)
        self.assertIn("smartStopEnabled", cfg)

    def test_apply_config_is_sequential_with_previous_rollback(self):
        client_h = (ROOT / "ChargeLimiter" / "UIKit" / "ChargeGuard" / "CGDaemonClient.h").read_text(encoding="utf-8")
        client_m = (ROOT / "ChargeLimiter" / "UIKit" / "ChargeGuard" / "CGDaemonClient.m").read_text(encoding="utf-8")
        self.assertIn("previousConfig", client_h)
        # Sequential: next key is written only from the previous key's callback.
        self.assertIn("writeKeys:", client_m)
        self.assertIn("index:index + 1", client_m)
        # No parallel fan-out: the old remaining-counter pattern must be gone.
        self.assertNotIn("remaining -= 1", client_m)
        # Rollback re-writes the previous config on failure, still reporting it.
        self.assertIn("prevDict", client_m)

    def test_main_view_passes_previous_config(self):
        main = (ROOT / "ChargeLimiter" / "UIKit" / "ChargeGuard" / "CGMainViewController.m").read_text(encoding="utf-8")
        self.assertIn("previousConfig:previous", main)
        self.assertIn("CGConfig *previous = self.config;", main)

    def test_all_three_app_targets_build_chargeguard_app(self):
        # Overnight find: the rootful app target (ChargeLimiter) still used
        # PRODUCT_NAME=$(TARGET_NAME), which would build ChargeLimiter.app
        # and break the daemon Run Script cp to ChargeGuard.app — the exact
        # v2.0 failure, for the rootful variant only. Rootless/roothide were
        # already explicit. Daemon targets intentionally keep $(TARGET_NAME):
        # their Run Scripts copy the binary to a fixed ChargeGuard.app path.
        import re
        pbx = (ROOT / "ChargeGuard.xcodeproj" / "project.pbxproj").read_text(encoding="utf-8")
        app_config_ids = [
            "184EA9B52B7A373300D0981D", "184EA9B62B7A373300D0981D",  # rootless
            "187886472B51976B00E48B28", "187886482B51976B00E48B28",  # rootful
            "571E8045A68143E499121E25", "9F376CCD6DF740FBA398B9CB",  # roothide
        ]
        for cid in app_config_ids:
            block = re.search(re.escape(cid) + r" /\* (?:Debug|Release) \*/ = \{.*?PRODUCT_NAME = ([^;]+);", pbx, re.S)
            self.assertIsNotNone(block, f"config {cid} not found")
            self.assertEqual(block.group(1).strip(), "ChargeGuard", f"config {cid} PRODUCT_NAME")


class V3OvernightPackagingTests(unittest.TestCase):
    def test_rootless_plist_path_not_doubled(self):
        plist = (ROOT / "ChargeLimiter" / "Package_rootless" / "var" / "jb" / "Library" / "LaunchDaemons" / "com.chargeguard.plist").read_text(encoding="utf-8")
        self.assertNotIn("/var/jb/var/jb/", plist)
        self.assertIn("/var/jb/usr/libexec/ChargeGuardDaemon", plist)

    def test_preference_loader_entry_staged_and_checked(self):
        import plistlib
        entry = plistlib.loads((ROOT / "ChargeLimiter" / "ChargeGuardSettings" / "ChargeGuard.plist").read_bytes())
        self.assertEqual(entry["entry"]["bundle"], "ChargeGuardSettings")
        self.assertEqual(entry["entry"]["label"], "ChargeGuard")
        script = (ROOT / "scripts" / "build_packages.sh").read_text(encoding="utf-8")
        self.assertIn("stage_settings_entry", script)
        self.assertIn("Library/PreferenceLoader/Preferences/ChargeGuard.plist", script)
        workflow = (ROOT / ".github" / "workflows" / "release.yml").read_text(encoding="utf-8")
        self.assertIn("Library/PreferenceLoader/Preferences/ChargeGuard.plist", workflow)

    def test_rootful_daemon_entitlements_exist(self):
        import re
        pbx = (ROOT / "ChargeGuard.xcodeproj" / "project.pbxproj").read_text(encoding="utf-8")
        for cid in ["18C123C62C8C08B300FAAC6C", "18C123C72C8C08B300FAAC6C"]:
            block = re.search(re.escape(cid) + r" /\* (?:Debug|Release) \*/ = \{.*?CODE_SIGN_ENTITLEMENTS = ([^;]+);", pbx, re.S)
            self.assertIsNotNone(block, cid)
            self.assertEqual(block.group(1).strip(), "ChargeLimiter/ChargeLimiter.entitlements")
        self.assertTrue((ROOT / "ChargeLimiter" / "ChargeLimiter.entitlements").exists())

    def test_roothide_postinst_daemon_bin_assigned_before_use(self):
        post = (ROOT / "ChargeLimiter" / "Package_roothide" / "DEBIAN" / "postinst").read_text(encoding="utf-8")
        assign = post.index('DAEMON_BIN="/usr/libexec/ChargeGuardDaemon"')
        # The old early chown on an empty DAEMON_BIN must be gone; ownership
        # is now applied to the jbroot-resolved REAL_DAEMON.
        self.assertNotIn('chown root:wheel "$DAEMON_BIN"', post)
        self.assertIn('chown root:wheel "$REAL_DAEMON"', post)
        self.assertLess(assign, post.index('REAL_DAEMON="$(jbroot'))
        self.assertIn('"$SED_BIN" "s|/usr/libexec/ChargeGuardDaemon|', post)

    def test_migration_covers_nonempty_new_dir_without_new_config(self):
        for variant in ["Package", "Package_rootless", "Package_roothide"]:
            post = (ROOT / "ChargeLimiter" / variant / "DEBIAN" / "postinst").read_text(encoding="utf-8")
            self.assertIn('[ ! -e "$NEW_DATA_DIR/com.chargeguard.plist" ] && [ -e "$OLD_DATA_DIR/com.chargelimiter.mod.plist" ]', post)

    def test_utils_roothide_fallback_uses_new_data_dir(self):
        utils = (ROOT / "ChargeLimiter" / "utils.mm").read_text(encoding="utf-8")
        self.assertIn('@"var/mobile/ChargeGuard"', utils)
        self.assertNotIn('var/mobile/ChargeLimiter', utils)


class V3OvernightSafetyTests(unittest.TestCase):
    def test_legacy_migration_recognises_old_config_filename(self):
        utils = (ROOT / "ChargeLimiter" / "utils.mm").read_text(encoding="utf-8")
        self.assertIn('@"com.chargelimiter.mod.plist"', utils)

    def test_language_switch_does_not_force_config_read_attempted(self):
        main = (ROOT / "ChargeLimiter" / "UIKit" / "Controllers" / "CLSettingsViewController.m").read_text(encoding="utf-8")
        # languageDidChange must render from existing flags, not call
        # configDidUpdate (which sets configReadAttempted=YES unconditionally).
        import re
        # There are several languageDidChange methods in this file; take the
        # settings one (it rebuilds UI and refreshes battery info).
        blocks = re.findall(r"- \(void\)languageDidChange \{(.*?)\n\}", main, re.S)
        settings_blocks = [b for b in blocks if "batteryInfoDidUpdate" in b]
        self.assertTrue(settings_blocks, "settings languageDidChange not found")
        block = settings_blocks[0]
        self.assertIn("updateConfigReadStatus", block)
        self.assertNotIn("[self configDidUpdate]", block)

    def test_settings_bundle_cross_validates_threshold_pairs(self):
        ctrl = (ROOT / "ChargeLimiter" / "ChargeGuardSettings" / "CLChargeGuardPrefsController.m").read_text(encoding="utf-8")
        self.assertIn('@"charge_temp_below"', ctrl)
        self.assertIn("charge_temp_above", ctrl)
        # Cross-check logic must exist beyond the per-key range gate.
        self.assertIn("cross-check", ctrl.lower())

    def test_cg_slider_registers_touch_cancel(self):
        main = (ROOT / "ChargeLimiter" / "UIKit" / "ChargeGuard" / "CGMainViewController.m").read_text(encoding="utf-8")
        self.assertIn("UIControlEventTouchCancel", main)

    def test_roothide_plist_repair_guards_nil_suffix(self):
        utils = (ROOT / "ChargeLimiter" / "utils.mm").read_text(encoding="utf-8")
        self.assertIn("if (daemonSuffix == nil)", utils)

    def test_renamed_help_string_localised_both_locales(self):
        for loc in ["zh-Hans", "en"]:
            strings = (ROOT / "ChargeLimiter" / f"{loc}.lproj" / "Localizable.strings").read_text(encoding="utf-8")
            self.assertIn("ChargeGuard 是一款电池充电限制工具", strings)


class V3OvernightReviewATests(unittest.TestCase):
    def test_smart_switch_uses_predictive_key_not_use_smart_write(self):
        sub = (ROOT / "ChargeLimiter" / "UIKit" / "ChargeGuard" / "CGSubPages.m").read_text(encoding="utf-8")
        self.assertIn('@"adv_predictive_inhibit_charge"', sub)
        self.assertNotIn('key = @"use_smart"', sub)
        cfg = (ROOT / "ChargeLimiter" / "UIKit" / "ChargeGuard" / "CGConfig.m").read_text(encoding="utf-8")
        self.assertIn('@"adv_predictive_inhibit_charge"', cfg)
        # daemonDictionary must not write use_smart (runtime detection only).
        daemon_dict = cfg[cfg.index("- (NSDictionary *)daemonDictionary"):]
        self.assertNotIn('@\"use_smart\"', daemon_dict)

    def test_statistics_conf_names_buckets(self):
        client = (ROOT / "ChargeLimiter" / "UIKit" / "ChargeGuard" / "CGDaemonClient.m").read_text(encoding="utf-8")
        self.assertIn('@"min5"', client)
        self.assertIn('@"hour"', client)
        self.assertNotIn("getStatisticsWithConf:@{}", client)

    def test_apply_writes_only_changed_keys(self):
        client = (ROOT / "ChargeLimiter" / "UIKit" / "ChargeGuard" / "CGDaemonClient.m").read_text(encoding="utf-8")
        self.assertIn("isEqual:prevDict[key]", client)
        self.assertIn("rollbackKeys", client)

    def test_history_filter_selects_bucket_and_temp_normalised(self):
        sub = (ROOT / "ChargeLimiter" / "UIKit" / "ChargeGuard" / "CGSubPages.m").read_text(encoding="utf-8")
        self.assertIn("_filter.selectedIndex", sub)
        self.assertIn("bucketMinutes", sub)
        analytics = (ROOT / "ChargeLimiter" / "UIKit" / "ChargeGuard" / "CGHistoryAnalytics.m").read_text(encoding="utf-8")
        self.assertIn("temp > 200", analytics)

    def test_main_refreshes_on_return_and_serializes_writes(self):
        main = (ROOT / "ChargeLimiter" / "UIKit" / "ChargeGuard" / "CGMainViewController.m").read_text(encoding="utf-8")
        self.assertIn("writeInFlight", main)
        # viewWillAppear refreshes (A7): refreshAll appears in viewWillAppear.
        import re
        vwa = re.search(r"- \(void\)viewWillAppear:\(BOOL\)animated \{(.*?)\n\}", main, re.S)
        self.assertIsNotNone(vwa)
        self.assertIn("[self refreshAll]", vwa.group(1))

    def test_view_model_copies_config_and_gates_on_external(self):
        vm = (ROOT / "ChargeLimiter" / "UIKit" / "ChargeGuard" / "CGBatteryViewModel.m").read_text(encoding="utf-8")
        self.assertIn("_config = [config copy]", vm)
        self.assertIn("externalConnected", vm)
        self.assertIn('未连接电源', vm)

    def test_set_config_value_guards_nil_and_validates_live(self):
        client = (ROOT / "ChargeLimiter" / "UIKit" / "ChargeGuard" / "CGDaemonClient.m").read_text(encoding="utf-8")
        self.assertIn("key == nil || value == nil", client)
        self.assertIn("fetchConfigWithCompletion", client)


class V3SettingsBundleTests(unittest.TestCase):
    def test_controller_is_real_not_skeleton(self):
        ctrl = (ROOT / "ChargeLimiter" / "ChargeGuardSettings" / "CLChargeGuardPrefsController.m").read_text(encoding="utf-8")
        self.assertIn("PSSwitchCell", ctrl)
        self.assertIn("PSSliderCell", ctrl)
        self.assertIn('"set_conf"', ctrl)
        self.assertIn('"get_conf"', ctrl)
        self.assertNotIn("Real implementation (Theos build)", ctrl)
        self.assertNotIn("[[NSUserDefaults", ctrl)
        self.assertTrue((ROOT / "ChargeLimiter" / "ChargeGuardSettings" / "Makefile").exists())
        self.assertTrue((ROOT / "ChargeLimiter" / "ChargeGuardSettings" / "Info.plist").exists())


class V3BuildOnlyWorkflowTests(unittest.TestCase):
    """Step 2 preparation: build-only dispatch must not create a Release.

    Tag push still publishes exactly as before; only the Publish step
    (the sole step that runs `gh release`) is gated off by build_only,
    and build-only runs still get the 4 packages out via artifact upload.
    """

    def _workflow(self):
        return WORKFLOW.read_text(encoding="utf-8")

    def _step_block(self, workflow, name):
        # Step block = text from "- name: <name>" up to the next step.
        parts = workflow.split("- name: ")
        for part in parts[1:]:
            if part.startswith(name + "\n") or part.startswith(name + "\r"):
                return part
        self.fail(f"step {name!r} not found in release.yml")

    def test_build_only_input_exists_and_defaults_off(self):
        workflow = self._workflow()
        self.assertIn("build_only:", workflow)
        # Boolean input, off by default: a plain dispatch without the
        # input must still publish (same as before).
        block = workflow[workflow.index("build_only:"):workflow.index("build_only:") + 400]
        self.assertIn("type: boolean", block)
        self.assertIn("default: false", block)

    def test_tag_push_trigger_unchanged(self):
        workflow = self._workflow()
        self.assertIn('tags:\n      - "v*"', workflow)

    def test_publish_is_the_only_release_creating_step_and_is_gated(self):
        workflow = self._workflow()
        publish = self._step_block(workflow, "Publish GitHub Release")
        self.assertIn("if: ${{ !inputs.build_only }}", publish)
        self.assertIn("gh release", publish)
        # No other step may create/edit a release (notes step only writes a file).
        for name in ["Build packages", "Verify expected release assets",
                     "Generate release notes", "Upload build packages (build-only)"]:
            block = self._step_block(workflow, name)
            self.assertNotIn("gh release", block, name)

    def test_build_and_verify_are_not_gated_off(self):
        workflow = self._workflow()
        for name in ["Build packages", "Verify expected release assets"]:
            block = self._step_block(workflow, name)
            first_lines = "\n".join(block.splitlines()[:3])
            self.assertNotIn("if:", first_lines, name)

    def test_verify_still_checks_all_four_packages_and_deb_layout(self):
        workflow = self._workflow()
        verify = self._step_block(workflow, "Verify expected release assets")
        for asset in ["ChargeGuard_${TAG_VERSION}_TrollStore.tipa",
                      "ChargeGuard_${TAG_VERSION}_rootful_arm.deb",
                      "ChargeGuard_${TAG_VERSION}_rootless_arm64.deb",
                      "ChargeGuard_${TAG_VERSION}_roothide_arm64e.deb"]:
            self.assertIn(asset, verify, asset)
        self.assertIn("ChargeGuard.app", verify)
        self.assertIn("com.chargeguard", verify)
        self.assertIn('test ! -e "$TMP/Applications"', verify)
        self.assertIn("Library/PreferenceBundles/ChargeGuardSettings.bundle/Root.plist", verify)
        self.assertIn("Library/PreferenceLoader/Preferences/ChargeGuard.plist", verify)

    def test_build_only_uploads_packages_as_artifact(self):
        workflow = self._workflow()
        upload = self._step_block(workflow, "Upload build packages (build-only)")
        self.assertIn("if: ${{ inputs.build_only }}", upload)
        self.assertIn("actions/upload-artifact", upload)
        self.assertIn("out/ChargeGuard_*", upload)


if __name__ == "__main__":
    unittest.main()
