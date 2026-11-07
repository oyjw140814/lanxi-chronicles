"""Run native input/health/render checks in isolation so user saves stay untouched."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile


def main():
    source = Path(__file__).resolve().parents[1]
    stage = Path(tempfile.mkdtemp(prefix="lanxi-runtime-check-"))
    godot = os.environ.get("GODOT_BIN", str(Path.home() / "Downloads/Godot.app/Contents/MacOS/Godot"))
    for folder in ("scripts", "scenes", "shaders", "assets", "tests"):
        shutil.copytree(source / folder, stage / folder)
    shutil.copy2(source / "icon.svg", stage / "icon.svg")
    project = (source / "project.godot").read_text()
    project = project.replace('config/name="岚汐纪"', f'config/name="{stage.name}"')
    (stage / "project.godot").write_text(project)
    # Keep automation's synthetic gestures separate from the user's real pointer.
    # Only the temporary copy uses a non-interactive window; the shipped game
    # retains its normal focus, border and input behavior.
    main_script = stage / "scripts/main.gd"
    code = main_script.read_text().replace(
        "func _ready() -> void:\n",
        "func _ready() -> void:\n"
        "\tget_window().set_flag(Window.FLAG_NO_FOCUS, true)\n"
        "\tget_window().set_flag(Window.FLAG_MOUSE_PASSTHROUGH, true)\n"
        "\tget_window().borderless = true\n")
    main_script.write_text(code)
    results = stage / "builds"
    results.mkdir()
    (results / ".gdignore").touch()
    commands = [
        ("import", ["--headless", "--editor", "--import"]),
        ("runtime", ["--windowed", "--", "--visual-test"]),
        ("layout", ["--headless", "--script", "tests/window_layout.gd"]),
    ]
    try:
        for label, extra in commands:
            command = [godot, "--path", str(stage)] + extra
            completed = subprocess.run(command, capture_output=True, text=True, timeout=180)
            log = completed.stdout + completed.stderr
            (results / f"{label}.log").write_text(log)
            print(f"{label}: exit={completed.returncode}", flush=True)
            for line in log.splitlines():
                if any(marker in line for marker in ("SUMMARY", "INTEGRATION", "FAILURES", "COMPLETE", "ERROR")):
                    print(line, flush=True)
            expected = {"import": "Godot Engine", "runtime": "VISUAL_TEST_COMPLETE", "layout": "HUD_RESIZE_CHECKS"}[label]
            if completed.returncode or "ERROR:" in log or expected not in log or any(line.startswith("INTEGRATION ") and "=false" in line for line in log.splitlines()):
                raise RuntimeError(f"Check failed: {label}; see {results}")
    finally:
        destination = source / "builds/laptop-health"
        shutil.copytree(results, destination, dirs_exist_ok=True)
        print(f"Evidence: {destination}\nIsolated project: {stage}", flush=True)


if __name__ == "__main__":
    main()
