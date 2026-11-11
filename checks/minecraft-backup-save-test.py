import os
from pathlib import Path
import subprocess
import sys
import tempfile


pause_source, resume_source, environment_source, rcon = sys.argv[1:]
with tempfile.TemporaryDirectory() as directory:
    root = Path(directory)
    environment = root / "environment"
    environment.write_text("RCON_PASSWORD=test-only\n")
    log = root / "commands"
    mock = root / "mcrcon"
    mock.write_text(
        '#!/bin/sh\nprintf "%s %s\\n" "$4" "$5" >> "$COMMAND_LOG"\n'
        '[ "$5" != save-off ] || [ "$4" != "$FAIL_PORT" ] || exit 1\n'
        '[ "$5" != save-on ] || [ "$4" != "$FAIL_RESTORE" ]\n'
    )
    mock.chmod(0o755)
    pause, resume = root / "pause", root / "resume"
    for source, target in [(pause_source, pause), (resume_source, resume)]:
        text = Path(source).read_text()
        text = text.replace(environment_source, str(environment))
        text = text.replace(rcon, str(mock)).replace(resume_source, str(resume))
        target.write_text(text)
        target.chmod(0o755)

    ports = ["25575", "25576", "25577"]
    for failed, restore_failure in [("", ""), *[(port, "") for port in ports], ("25577", "25575")]:
        log.write_text("")
        result = subprocess.run(
            [pause],
            env=os.environ | {
                "COMMAND_LOG": str(log),
                "FAIL_PORT": failed,
                "FAIL_RESTORE": restore_failure,
            },
            capture_output=True,
            text=True,
        )
        calls = log.read_text().splitlines()
        assert result.returncode == bool(failed), (failed, result.stderr, calls)
        resumed = [line for line in calls if line.endswith(" save-on")]
        assert resumed == ([f"{port} save-on" for port in ports] if failed else []), calls
        if not failed:
            assert calls == [f"{port} save-off" for port in ports], calls
