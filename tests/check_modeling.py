"""Verify the actual model integration in a disposable project and user directory."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile


def main():
    source = Path(__file__).resolve().parents[1]
    stage = Path(tempfile.mkdtemp(prefix="LanXi-Modeling-"))
    output = source / "builds/modeling-20261017"
    output.mkdir(parents=True, exist_ok=True)
    godot = os.environ.get("GODOT_BIN", str(Path.home() / "Downloads/Godot.app/Contents/MacOS/Godot"))
    for name in ("scripts", "scenes", "shaders", "assets", "tests", "handoff"):
        shutil.copytree(source / name, stage / name)
    shutil.copy2(source / "icon.svg", stage / "icon.svg")
    project = (source / "project.godot").read_text()
    project = project.replace('[application]\n', '[application]\n'
        f'config/use_custom_user_dir=true\nconfig/custom_user_dir_name="{stage.name}"\n')
    (stage / "project.godot").write_text(project)
    (stage / "builds").mkdir()
    (stage / "builds/.gdignore").touch()
    # Synthetic input must not move or capture the user's real pointer.
    entry = stage / "scripts/main.gd"
    entry.write_text(entry.read_text().replace("func _ready() -> void:\n",
        "func _ready() -> void:\n"
        "\tget_window().set_flag(Window.FLAG_NO_FOCUS, true)\n"
        "\tget_window().set_flag(Window.FLAG_MOUSE_PASSTHROUGH, true)\n"
        "\tget_window().borderless = true\n"))
    checks = [
        ("import", ["--headless", "--editor", "--import"], "Godot Engine"),
        ("rules", ["--headless", "--script", "tests/sim_test.gd"], "SIMULATION TESTS:"),
        ("art-contract", ["--headless", "--script", "tests/art_contract.gd"], "ART_CONTRACT_SUMMARY"),
        ("art-result", ["--headless", "--script", "tests/art_result.gd"], "ART_RESULT_SUMMARY"),
        ("art-native", ["--windowed", "--audio-driver", "Dummy", "--script", "tests/art_native.gd"], "ART_SUMMARY"),
        ("runtime", ["--windowed", "--audio-driver", "Dummy", "--", "--visual-test"], "VISUAL_TEST_COMPLETE"),
        ("layout", ["--headless", "--script", "tests/window_layout.gd"], "HUD_RESIZE_CHECKS"),
    ]
    summary = {"stage": str(stage), "checks": []}
    try:
        for label, args, marker in checks:
            command = [godot, "--path", str(stage), "--log-file", str(output / f"{label}-engine.log")] + args
            completed = subprocess.run(command, capture_output=True, text=True, timeout=240)
            log = completed.stdout + completed.stderr
            (output / f"{label}.log").write_text(log)
            print(f"{label}: exit={completed.returncode}", flush=True)
            for line in log.splitlines():
                if any(m in line for m in ("SUMMARY", "INTEGRATION", "FAILURES", "COMPLETE", "SIMULATION TESTS")):
                    print(line, flush=True)
            summary["checks"].append({"name": label, "exit": completed.returncode})
            if completed.returncode or marker not in log or "ERROR:" in log or any(
                line.startswith("INTEGRATION ") and "=false" in line for line in log.splitlines()
            ):
                raise RuntimeError(f"Failed {label}; see {output / (label + '.log')}")
    finally:
        shutil.copytree(stage / "builds", output, dirs_exist_ok=True)
        (output / "run.json").write_text(json.dumps(summary, ensure_ascii=False, indent=2))
        print(f"Evidence: {output}\nStage: {stage}", flush=True)


if __name__ == "__main__":
    main()
