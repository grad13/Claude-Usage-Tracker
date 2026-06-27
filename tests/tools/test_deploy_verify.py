# meta: updated=2026-04-25 14:55 checked=-
"""Tests for the 5-gate deployment verification pipeline with self-repair.

Covers:
  Gate 1 (pluginkit):     correct path / wrong path / DerivedData ghost
  Gate 2 (lsregister):    clean / ghost path
  Gate 3 (finderinfo):    bundle bit set / bit unset / xattr missing
  Gate 4 (smoke launch):  open success / open fail / wrong path
  Gate 5 (widget runtime): /Applications path / DerivedData path / no process
  Self-repair wrapper:    pass-after-repair / fail-after-repair
  cleanup_stale_lsregister: filters paths correctly
  widget_running_path:    parses ps output correctly
"""

import sys
from pathlib import Path
from unittest.mock import patch

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent.parent / "code" / "tools"))
sys.path.insert(0, str(Path(__file__).resolve().parent.parent.parent / "code" / "tools" / "lib"))


APP_PATH = "/Applications/ClaudeUsageTracker.app"
APPEX_PATH = (
    "/Applications/ClaudeUsageTracker.app/Contents/PlugIns/"
    "ClaudeUsageTrackerWidgetExtension.appex"
)
WIDGET_ID = "grad13.claudeusagetracker.widget"


# ---------------------------------------------------------------------------
# Gate 1: pluginkit
# ---------------------------------------------------------------------------

class TestGatePluginkit:
    def test_correct_path_passes(self, make_run_result):
        import build_and_install as bi
        pk_stdout = f"+    {WIDGET_ID}(0.1.0)\tUUID\t2026-04-25\t{APPEX_PATH}\n (1 plug-in)\n"
        with patch.object(bi, "run", return_value=make_run_result(stdout=pk_stdout)):
            bi._gate_pluginkit(APP_PATH)  # should not raise

    def test_widget_not_found_fails(self, make_run_result):
        import build_and_install as bi
        with patch.object(bi, "run", return_value=make_run_result(stdout="")):
            with pytest.raises(bi.GateFailure) as exc:
                bi._gate_pluginkit(APP_PATH)
            assert "Widget not found" in exc.value.detail

    def test_derived_data_ghost_fails(self, make_run_result):
        import build_and_install as bi
        ghost = (
            f"+    {WIDGET_ID}(0.1.0)\tUUID\tdate\t"
            f"/Users/x/Library/Developer/Xcode/DerivedData/.../ClaudeUsageTrackerWidgetExtension.appex\n"
        )
        with patch.object(bi, "run", return_value=make_run_result(stdout=ghost)):
            with pytest.raises(bi.GateFailure) as exc:
                bi._gate_pluginkit(APP_PATH)
            assert "DerivedData" in exc.value.detail or "unexpected" in exc.value.detail

    def test_build_dir_ghost_fails(self, make_run_result):
        import build_and_install as bi
        ghost = (
            f"+    {WIDGET_ID}(0.1.0)\tUUID\tdate\t"
            f"/Users/x/proj/build/export/ClaudeUsageTracker.app/Contents/PlugIns/"
            f"ClaudeUsageTrackerWidgetExtension.appex\n"
        )
        with patch.object(bi, "run", return_value=make_run_result(stdout=ghost)):
            with pytest.raises(bi.GateFailure):
                bi._gate_pluginkit(APP_PATH)


# ---------------------------------------------------------------------------
# Gate 2: lsregister
# ---------------------------------------------------------------------------

class TestGateLsregister:
    def test_clean_passes(self, make_run_result):
        import build_and_install as bi
        dump = (
            "path:                       /Applications/ClaudeUsageTracker.app (0x4d50)\n"
            "directory:                  /Applications\n"
            "path:                       /Applications/ClaudeUsageTracker.app/Contents/PlugIns/"
            "ClaudeUsageTrackerWidgetExtension.appex (0x4d54)\n"
        )
        with patch.object(bi, "run", return_value=make_run_result(stdout=dump)):
            bi._gate_lsregister(APP_PATH)

    def test_live_ghost_app_fails(self, make_run_result):
        """A ghost path that EXISTS on disk is a real failure."""
        import build_and_install as bi
        dump = (
            "path:                       /Applications/ClaudeUsageTracker.app (0x4d50)\n"
            "path:                       /Users/x/build/export/ClaudeUsageTracker.app (0x19a8)\n"
        )
        with patch.object(bi, "run", return_value=make_run_result(stdout=dump)), \
             patch("build_and_install.Path.exists", return_value=True):
            with pytest.raises(bi.GateFailure) as exc:
                bi._gate_lsregister(APP_PATH)
            assert "build/export" in exc.value.detail

    def test_appex_ghost_ignored_by_gate2(self, make_run_result):
        """Gate-2 intentionally ignores .appex paths — those are the
        responsibility of Gate-1 (pluginkit) and Gate-5 (runtime).
        `lsregister -u` cannot reliably remove a fresh DerivedData appex
        anyway, so checking it here would always fail."""
        import build_and_install as bi
        dump = (
            "path:                       /Applications/ClaudeUsageTracker.app (0x4d50)\n"
            "path:                       /Users/x/Library/Developer/Xcode/DerivedData/abc/"
            "Build/Products/Debug/ClaudeUsageTracker.app/Contents/PlugIns/"
            "ClaudeUsageTrackerWidgetExtension.appex (0x4d44)\n"
        )
        with patch.object(bi, "run", return_value=make_run_result(stdout=dump)), \
             patch("build_and_install.Path.exists", return_value=True):
            bi._gate_lsregister(APP_PATH)  # should NOT raise — appex is out of scope

    def test_dead_ghost_passes(self, make_run_result):
        """A ghost path that no longer exists on disk should be ignored
        (LaunchServices will GC it; chronod won't load it)."""
        import build_and_install as bi
        dump = (
            "path:                       /Applications/ClaudeUsageTracker.app (0x4d50)\n"
            "path:                       /Users/x/Library/Developer/Xcode/DerivedData/abc/"
            "Build/Products/Debug/ClaudeUsageTracker.app/Contents/PlugIns/"
            "ClaudeUsageTrackerWidgetExtension.appex (0x4d44)\n"
        )
        with patch.object(bi, "run", return_value=make_run_result(stdout=dump)), \
             patch("build_and_install.Path.exists", return_value=False):
            bi._gate_lsregister(APP_PATH)  # should not raise


# ---------------------------------------------------------------------------
# Gate 3: FinderInfo bundle bit
# ---------------------------------------------------------------------------

class TestGateFinderInfo:
    def test_bundle_bit_set_passes(self, make_run_result):
        import build_and_install as bi
        # byte 8 = 0x20 (kHasBundle bit)
        hex_out = "00 00 00 00 00 00 00 00 20 00 00 00 00 00 00 00\n"
        with patch.object(bi, "run", return_value=make_run_result(stdout=hex_out)):
            bi._gate_finderinfo(APP_PATH)

    def test_bundle_bit_unset_fails(self, make_run_result):
        import build_and_install as bi
        # byte 8 = 0x00 (no bundle bit)
        hex_out = "00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00\n"
        with patch.object(bi, "run", return_value=make_run_result(stdout=hex_out)):
            with pytest.raises(bi.GateFailure) as exc:
                bi._gate_finderinfo(APP_PATH)
            assert "Bundle bit" in exc.value.detail

    def test_finderinfo_missing_passes(self, make_run_result):
        """xattr returns nonzero when the attribute is missing — that's OK."""
        import build_and_install as bi
        with patch.object(bi, "run",
                          return_value=make_run_result(returncode=1, stderr="No such xattr")):
            bi._gate_finderinfo(APP_PATH)  # should not raise

    def test_finderinfo_truncated_fails(self, make_run_result):
        import build_and_install as bi
        with patch.object(bi, "run", return_value=make_run_result(stdout="00 00 00")):
            with pytest.raises(bi.GateFailure) as exc:
                bi._gate_finderinfo(APP_PATH)
            assert "too short" in exc.value.detail


# ---------------------------------------------------------------------------
# Gate 4: smoke launch
# ---------------------------------------------------------------------------

class TestGateSmokeLaunch:
    def test_launches_from_correct_path(self, make_run_result):
        import build_and_install as bi
        expected_bin = f"{APP_PATH}/Contents/MacOS/ClaudeUsageTracker"

        # Sequence of `run` calls during the gate:
        # 1. killall (pre-smoke)
        # 2. open
        # 3. pgrep (loop) — returns the process line
        # 4. killall (post-smoke)
        call_log: list[list[str]] = []

        def fake_run(cmd, **kwargs):
            call_log.append(cmd)
            if cmd[0] == "open":
                return make_run_result(returncode=0)
            if cmd[0] == "pgrep":
                return make_run_result(stdout=f"12345 {expected_bin}\n")
            return make_run_result()

        with patch.object(bi, "run", side_effect=fake_run), \
             patch("build_and_install.time.sleep"):
            bi._gate_smoke_launch(APP_PATH)
        assert any(c[0] == "open" for c in call_log)

    def test_open_failure_fails(self, make_run_result):
        import build_and_install as bi

        def fake_run(cmd, **kwargs):
            if cmd[0] == "open":
                return make_run_result(returncode=1, stderr="LSOpenURLsWithRole error")
            return make_run_result()

        with patch.object(bi, "run", side_effect=fake_run), \
             patch("build_and_install.time.sleep"):
            with pytest.raises(bi.GateFailure) as exc:
                bi._gate_smoke_launch(APP_PATH)
            assert "open" in exc.value.detail

    def test_process_not_appearing_fails(self, make_run_result):
        import build_and_install as bi

        def fake_run(cmd, **kwargs):
            if cmd[0] == "open":
                return make_run_result(returncode=0)
            if cmd[0] == "pgrep":
                return make_run_result(stdout="")  # never appears
            return make_run_result()

        with patch.object(bi, "run", side_effect=fake_run), \
             patch("build_and_install.time.monotonic", side_effect=[0.0, 100.0]), \
             patch("build_and_install.time.sleep"):
            with pytest.raises(bi.GateFailure) as exc:
                bi._gate_smoke_launch(APP_PATH)
            assert "did not start" in exc.value.detail

    def test_wrong_path_fails(self, make_run_result):
        import build_and_install as bi
        wrong_bin = "/Users/x/Library/Developer/Xcode/DerivedData/abc/Debug/ClaudeUsageTracker.app/Contents/MacOS/ClaudeUsageTracker"

        def fake_run(cmd, **kwargs):
            if cmd[0] == "open":
                return make_run_result(returncode=0)
            if cmd[0] == "pgrep":
                return make_run_result(stdout=f"12345 {wrong_bin}\n")
            return make_run_result()

        with patch.object(bi, "run", side_effect=fake_run), \
             patch("build_and_install.time.sleep"):
            with pytest.raises(bi.GateFailure) as exc:
                bi._gate_smoke_launch(APP_PATH)
            assert "wrong path" in exc.value.detail


# ---------------------------------------------------------------------------
# Gate 5: widget runtime path
# ---------------------------------------------------------------------------

class TestGateWidgetRuntime:
    def test_correct_path_passes(self, make_run_result):
        import build_and_install as bi
        with patch.object(bi, "widget_running_path",
                          return_value=f"{APPEX_PATH}/Contents/MacOS/ClaudeUsageTrackerWidgetExtension"):
            bi._gate_widget_runtime_path(APP_PATH)

    def test_derived_data_path_fails(self, make_run_result):
        import build_and_install as bi
        wrong = (
            "/Users/x/Library/Developer/Xcode/DerivedData/abc/Build/Products/Debug/"
            "ClaudeUsageTracker.app/Contents/PlugIns/ClaudeUsageTrackerWidgetExtension.appex/"
            "Contents/MacOS/ClaudeUsageTrackerWidgetExtension"
        )
        with patch.object(bi, "widget_running_path", return_value=wrong):
            with pytest.raises(bi.GateFailure) as exc:
                bi._gate_widget_runtime_path(APP_PATH)
            assert "wrong path" in exc.value.detail

    def test_no_process_passes_with_skip(self, make_run_result, capsys):
        import build_and_install as bi
        with patch.object(bi, "widget_running_path", return_value=None):
            bi._gate_widget_runtime_path(APP_PATH)
        out = capsys.readouterr().out
        assert "skip" in out.lower()


# ---------------------------------------------------------------------------
# Min-OS gate (deployment-target invariant)
# ---------------------------------------------------------------------------

class TestVerifyMinOs:
    """verify_min_os() fails the deploy if any bundled Mach-O binary's minos
    exceeds the advertised macOS floor (14.0). Regression guard for the
    framework-at-26.2 / widget-at-14.6 SDK auto-bump that broke the widget on
    end-user Macs."""

    MACHO = b"\xcf\xfa\xed\xfe" + b"\x00" * 16  # MH_MAGIC_64 + padding

    def _make_app(self, tmp_path):
        app = tmp_path / "ClaudeUsageTracker.app"
        (app / "Contents/MacOS").mkdir(parents=True)
        (app / "Contents/MacOS/ClaudeUsageTracker").write_bytes(self.MACHO)
        fw = app / "Contents/Frameworks/ClaudeUsageTrackerShared.framework/Versions/A"
        fw.mkdir(parents=True)
        (fw / "ClaudeUsageTrackerShared").write_bytes(self.MACHO)
        appex = (app / "Contents/PlugIns/ClaudeUsageTrackerWidgetExtension.appex"
                 / "Contents/MacOS")
        appex.mkdir(parents=True)
        (appex / "ClaudeUsageTrackerWidgetExtension").write_bytes(self.MACHO)
        # a non-binary resource that must be skipped without invoking vtool
        (app / "Contents/Info.plist").write_bytes(b"<?xml version='1.0'?>")
        return app

    def test_all_at_floor_passes(self, tmp_path, capsys):
        import build_and_install as bi
        app = self._make_app(tmp_path)
        with patch.object(bi, "_macho_minos", return_value=(14, 0)):
            bi.verify_min_os(str(app))  # should not raise
        assert "Min-OS gate verified" in capsys.readouterr().out

    def test_framework_above_floor_fails(self, tmp_path):
        import build_and_install as bi
        app = self._make_app(tmp_path)

        def fake(p):
            return (26, 2) if p.endswith("ClaudeUsageTrackerShared") else (14, 0)

        with patch.object(bi, "_macho_minos", side_effect=fake):
            with pytest.raises(RuntimeError) as exc:
                bi.verify_min_os(str(app))
        msg = str(exc.value)
        assert "26.2" in msg
        assert "ClaudeUsageTrackerShared" in msg

    def test_widget_above_floor_fails(self, tmp_path):
        import build_and_install as bi
        app = self._make_app(tmp_path)

        def fake(p):
            return (14, 6) if p.endswith("ClaudeUsageTrackerWidgetExtension") else (14, 0)

        with patch.object(bi, "_macho_minos", side_effect=fake):
            with pytest.raises(RuntimeError) as exc:
                bi.verify_min_os(str(app))
        assert "14.6" in str(exc.value)

    def test_non_macho_files_skipped_without_vtool(self, tmp_path):
        """Resources (plist etc.) are skipped via magic-byte check, so vtool
        (here _macho_minos) is never invoked on them."""
        import build_and_install as bi
        app = tmp_path / "ClaudeUsageTracker.app"
        (app / "Contents").mkdir(parents=True)
        (app / "Contents/Info.plist").write_bytes(b"<?xml version='1.0'?>")
        (app / "Contents/Assets.car").write_bytes(b"\x00\x01\x02\x03not-macho")
        with patch.object(bi, "_macho_minos", side_effect=AssertionError(
                "vtool should not run on non-Mach-O files")):
            bi.verify_min_os(str(app))  # should not raise

    def test_is_macho_detects_magic(self, tmp_path):
        import build_and_install as bi
        macho = tmp_path / "bin"
        macho.write_bytes(b"\xcf\xfa\xed\xfe\x00\x00")
        text = tmp_path / "plist"
        text.write_bytes(b"<?xml version='1.0'?>")
        assert bi._is_macho(str(macho)) is True
        assert bi._is_macho(str(text)) is False
        assert bi._is_macho(str(tmp_path / "missing")) is False

    def test_macho_minos_parses_vtool_output(self, make_run_result):
        import build_and_install as bi
        out = " platform MACOS\n    minos 14.0\n      sdk 26.5\n"
        with patch.object(bi, "run", return_value=make_run_result(stdout=out)):
            assert bi._macho_minos("/x/bin") == (14, 0)

    def test_macho_minos_none_for_non_macho(self, make_run_result):
        import build_and_install as bi
        with patch.object(
            bi, "run",
            return_value=make_run_result(returncode=1, stderr="not a Mach-O file"),
        ):
            assert bi._macho_minos("/x/Info.plist") is None


# ---------------------------------------------------------------------------
# Self-repair wrapper
# ---------------------------------------------------------------------------

class TestSelfRepair:
    def test_passes_first_attempt_no_repair(self):
        import build_and_install as bi
        gate_calls = [0]
        repair_calls = [0]

        def gate(_):
            gate_calls[0] += 1
        def repair(_):
            repair_calls[0] += 1

        bi._verify_with_self_repair("test", gate, repair, APP_PATH)
        assert gate_calls[0] == 1
        assert repair_calls[0] == 0

    def test_passes_after_repair(self):
        import build_and_install as bi
        gate_calls = [0]

        def gate(_):
            gate_calls[0] += 1
            if gate_calls[0] == 1:
                raise bi.GateFailure("test", "first attempt fail")
        def repair(_):
            pass

        bi._verify_with_self_repair("test", gate, repair, APP_PATH)
        assert gate_calls[0] == 2

    def test_persistent_failure_aborts(self):
        import build_and_install as bi

        def gate(_):
            raise bi.GateFailure("test", "always fails")
        def repair(_):
            pass

        with pytest.raises(RuntimeError) as exc:
            bi._verify_with_self_repair("test", gate, repair, APP_PATH)
        assert "GATE FAIL after self-repair" in str(exc.value)

    def test_repair_exception_is_caught_and_retry_runs(self):
        """If the repair itself raises, we still retry the gate (best effort)."""
        import build_and_install as bi
        gate_calls = [0]

        def gate(_):
            gate_calls[0] += 1
            if gate_calls[0] == 1:
                raise bi.GateFailure("test", "first attempt fail")
        def repair(_):
            raise RuntimeError("repair exploded")

        bi._verify_with_self_repair("test", gate, repair, APP_PATH)
        assert gate_calls[0] == 2  # second attempt ran despite repair raising


# ---------------------------------------------------------------------------
# launchservices helpers
# ---------------------------------------------------------------------------

class TestCleanupStaleLsregister:
    def test_filters_to_install_dir(self, make_run_result):
        import launchservices as ls
        dump = (
            "path:                       /Applications/ClaudeUsageTracker.app (0x4d50)\n"
            "path:                       /Users/x/build/export/ClaudeUsageTracker.app (0x19a8)\n"
            "path:                       /Users/x/Library/Developer/Xcode/DerivedData/abc/"
            "Build/Products/Debug/ClaudeUsageTracker.app/Contents/PlugIns/"
            "ClaudeUsageTrackerWidgetExtension.appex (0x4d44)\n"
            "path:                       /Applications/ClaudeUsageTracker.app/Contents/PlugIns/"
            "ClaudeUsageTrackerWidgetExtension.appex (0x4d54)\n"
            "path:                       /Some/Other/App.app (0x9999)\n"
        )
        unregistered: list[list[str]] = []

        def fake_run(cmd, **kwargs):
            if "-dump" in cmd:
                return make_run_result(stdout=dump)
            if "-u" in cmd:
                unregistered.append(cmd)
            return make_run_result()

        with patch.object(ls, "run", side_effect=fake_run):
            n = ls.cleanup_stale_lsregister("ClaudeUsageTracker", Path("/Applications"))
        assert n == 2
        # appex should be unregistered before .app (.appex first sort)
        appex_ix = next(i for i, c in enumerate(unregistered) if ".appex" in c[2])
        app_ix = next(i for i, c in enumerate(unregistered) if "build/export" in c[2])
        assert appex_ix < app_ix
        # Clean paths NOT touched
        cleaned_paths = [c[2] for c in unregistered]
        assert APP_PATH not in cleaned_paths
        assert "/Some/Other/App.app" not in cleaned_paths


class TestWidgetRunningPath:
    def test_returns_command_path(self, make_run_result):
        import launchservices as ls
        path = "/Applications/ClaudeUsageTracker.app/Contents/PlugIns/ClaudeUsageTrackerWidgetExtension.appex/Contents/MacOS/ClaudeUsageTrackerWidgetExtension"

        def fake_run(cmd, **kwargs):
            if cmd[0] == "pgrep":
                return make_run_result(stdout="12345\n")
            if cmd[0] == "ps":
                return make_run_result(stdout=f"{path} -LaunchArguments xyz\n")
            return make_run_result()

        with patch.object(ls, "run", side_effect=fake_run):
            assert ls.widget_running_path("ClaudeUsageTrackerWidgetExtension") == path

    def test_no_process_returns_none(self, make_run_result):
        import launchservices as ls
        with patch.object(ls, "run", return_value=make_run_result(stdout="")):
            assert ls.widget_running_path("ClaudeUsageTrackerWidgetExtension") is None
