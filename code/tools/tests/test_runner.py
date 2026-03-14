"""Tests for lib/runner.py."""
import subprocess
import sys
from pathlib import Path
from unittest.mock import patch

import pytest

sys.path.insert(0, str(Path(__file__).parent.parent / "lib"))

from runner import run


@pytest.fixture(autouse=True)
def _patch_subprocess():
    """Prevent actual subprocess calls."""
    with patch("runner.subprocess.run") as mock_run:
        mock_run.return_value = subprocess.CompletedProcess(
            args=["echo"], returncode=0, stdout="ok\n", stderr=""
        )
        yield mock_run


def test_run_success(_patch_subprocess):
    """Successful command returns CompletedProcess."""
    result = run(["echo", "hello"], label="test")
    assert result.returncode == 0
    assert result.stdout == "ok\n"


def test_run_check_raises_on_failure(_patch_subprocess):
    """check=True (default) raises RuntimeError on non-zero exit."""
    _patch_subprocess.return_value = subprocess.CompletedProcess(
        args=["false"], returncode=1, stdout="", stderr="command failed"
    )
    with pytest.raises(RuntimeError, match="rc=1"):
        run(["false"], label="test cmd")


def test_run_label_in_error_message(_patch_subprocess):
    """Label is included in the error message."""
    _patch_subprocess.return_value = subprocess.CompletedProcess(
        args=["bad"], returncode=42, stdout="", stderr="oops"
    )
    with pytest.raises(RuntimeError, match=r"\[my label\].*rc=42.*oops"):
        run(["bad"], label="my label")


def test_run_allow_fail_warns(_patch_subprocess, capsys):
    """allow_fail=True logs WARNING but does not raise."""
    _patch_subprocess.return_value = subprocess.CompletedProcess(
        args=["fail"], returncode=1, stdout="", stderr="not fatal"
    )
    result = run(["fail"], allow_fail=True, label="soft")
    assert result.returncode == 1
    captured = capsys.readouterr()
    assert "WARNING" in captured.err
    assert "soft" in captured.err


def test_run_check_false_warns(_patch_subprocess, capsys):
    """check=False logs WARNING but does not raise."""
    _patch_subprocess.return_value = subprocess.CompletedProcess(
        args=["fail"], returncode=1, stdout="", stderr="info"
    )
    result = run(["fail"], check=False, label="optional")
    assert result.returncode == 1
    captured = capsys.readouterr()
    assert "WARNING" in captured.err


def test_run_no_label(_patch_subprocess):
    """Error message without label has no prefix brackets."""
    _patch_subprocess.return_value = subprocess.CompletedProcess(
        args=["bad"], returncode=1, stdout="", stderr="err"
    )
    with pytest.raises(RuntimeError, match="^rc=1"):
        run(["bad"])


def test_run_passes_capture_output(_patch_subprocess):
    """Verify subprocess.run is called with capture_output=True, text=True."""
    run(["echo"])
    _patch_subprocess.assert_called_once_with(
        ["echo"], capture_output=True, text=True
    )
