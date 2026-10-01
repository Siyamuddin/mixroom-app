"""Control-path tests; no real containers or Docker settings are modified."""
import importlib.util
from pathlib import Path
from types import SimpleNamespace
import subprocess
from unittest.mock import Mock

import pytest

spec = importlib.util.spec_from_file_location("docker_local", Path(__file__).parents[1] / "scripts/docker_local.py")
helper = importlib.util.module_from_spec(spec)
spec.loader.exec_module(helper)


def socket_fixture():
    raw = Mock()
    raw.exists.return_value = True
    raw.is_socket.return_value = True
    raw.__str__ = Mock(return_value="/fixture/docker.raw.sock")
    return raw


def test_responsive_default_never_switches_docker_host():
    run = Mock(return_value=SimpleNamespace(returncode=0, stdout="28.4.0\n"))
    raw = socket_fixture()
    assert helper.docker_command(run, raw) == ["docker"]
    assert run.call_count == 1
    raw.exists.assert_not_called()
    assert run.call_args.kwargs["timeout"] == 5


def test_timed_out_proxy_uses_only_a_responsive_scoped_socket():
    run = Mock(side_effect=[subprocess.TimeoutExpired("docker", 5), SimpleNamespace(returncode=0, stdout="28.4.0\n")])
    result = helper.docker_command(run, socket_fixture())
    assert result == ["docker", "--host", "unix:///fixture/docker.raw.sock"]
    assert run.call_count == 2
    assert all(call.kwargs["timeout"] == 5 for call in run.call_args_list)


def test_missing_socket_does_not_try_an_unrelated_endpoint():
    run = Mock(return_value=SimpleNamespace(returncode=1, stdout=""))
    raw = socket_fixture(); raw.exists.return_value = False
    with pytest.raises(RuntimeError, match="not responding"): helper.docker_command(run, raw)
    assert run.call_count == 1


def test_unresponsive_fallback_reports_failure_without_resetting_daemon():
    run = Mock(side_effect=subprocess.TimeoutExpired("docker", 5))
    with pytest.raises(RuntimeError, match="No Docker settings were changed"):
        helper.docker_command(run, socket_fixture())
    assert run.call_count == 2
    assert all("version" in call.args[0] for call in run.call_args_list)
