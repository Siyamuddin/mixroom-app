#!/usr/bin/env python3
"""Run Docker commands for this backend, with a scoped macOS socket fallback.

Example from the repository root:
    python3 voice_backend/scripts/docker_local.py compose up -d --no-build

No global Docker context, environment file, or daemon is changed by this helper.
"""
from pathlib import Path
import subprocess
import sys


def responsive(prefix, run=subprocess.run):
    try:
        result = run([*prefix, "version", "--format", "{{.Server.Version}}"],
                     capture_output=True, text=True, timeout=5, check=False)
        return result.returncode == 0 and bool(result.stdout.strip())
    except (OSError, subprocess.TimeoutExpired):
        return False


def docker_command(run=subprocess.run, raw_socket=None):
    standard = ["docker"]
    if responsive(standard, run): return standard
    raw_socket = raw_socket or Path.home() / "Library/Containers/com.docker.docker/Data/docker.raw.sock"
    if raw_socket.exists() and raw_socket.is_socket():
        fallback = ["docker", "--host", "unix://" + str(raw_socket)]
        if responsive(fallback, run): return fallback
    raise RuntimeError("Docker is not responding. Open Docker Desktop and try again. No Docker settings were changed.")


def main(arguments=None):
    arguments = sys.argv[1:] if arguments is None else arguments
    if not arguments:
        print("Usage: python3 scripts/docker_local.py compose <command> [arguments]", file=sys.stderr)
        return 2
    try:
        prefix = docker_command()
        if len(prefix) > 1:
            print("Using Docker Desktop's responsive local socket for this command.", file=sys.stderr)
        result = subprocess.run([*prefix, *arguments], cwd=Path(__file__).resolve().parents[1], check=False)
        return result.returncode
    except (OSError, RuntimeError) as error:
        # No command arguments, environment variables, or credentials are logged.
        print(str(error) if isinstance(error, RuntimeError) else "The Docker command could not be started.", file=sys.stderr)
        return 1
    except KeyboardInterrupt:
        return 130


if __name__ == "__main__":
    sys.exit(main())
