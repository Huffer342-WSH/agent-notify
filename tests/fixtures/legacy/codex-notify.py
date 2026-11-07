#!/usr/bin/env python3
"""Compatibility entry point. Use agent-notify.py for new integrations."""

import runpy
from pathlib import Path

if __name__ == "__main__":
    runpy.run_path(str(Path(__file__).with_name("agent-notify.py")), run_name="__main__")
