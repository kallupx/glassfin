#!/usr/bin/env python3
"""Throwaway validation only: pace the pinned ffmpeg after fixture generation."""

import os
from pathlib import Path

if os.environ.get("CI") != "true":
    raise RuntimeError("validation media pacing runs only in CI")
root = Path(os.environ["RUNNER_TEMP"]) / (
    f"glassfin-e2e-{os.environ['GITHUB_RUN_ID']}-{os.environ['GITHUB_RUN_ATTEMPT']}")
binary = root / "ffmpeg/ffmpeg"
binary.rename(binary.with_name("ffmpeg-validated"))
binary.write_text('''#!/usr/bin/env python3
import os
from pathlib import Path
import sys

binary = Path(__file__).with_name("ffmpeg-validated")
arguments = sys.argv[1:]
if "-i" in arguments:
    index = arguments.index("-i")
    arguments[index:index] = ["-readrate", "1"]
os.execv(str(binary), [str(binary), *arguments])
''')
binary.chmod(0o700)
