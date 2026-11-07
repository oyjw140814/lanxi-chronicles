"""Run the real Godot Editor Play entry point against an isolated project copy."""
import argparse
import os
from pathlib import Path
import shutil
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default=os.environ.get(
        "GODOT_BIN", str(Path.home() / "Downloads/Godot.app/Contents/MacOS/Godot")))
    args = parser.parse_args()
    source = Path(__file__).resolve().parents[1]
    stage = Path(tempfile.mkdtemp(prefix="lanxi-editor-launch-"))
    fixtures = source / "tests/editor_launch"
    for folder in ("scripts", "scenes", "shaders", "assets"):
        shutil.copytree(source / folder, stage / folder)
    shutil.copy2(source / "icon.svg", stage / "icon.svg")
    project = (source / "project.godot").read_text()
    project = project.replace('config/name="岚汐纪"', 'config/name="LanxiEditorLaunchCheck"')
    project += '\n[editor_plugins]\nenabled=PackedStringArray("res://addons/launch_check/plugin.cfg")\n'
    (stage / "project.godot").write_text(project)
    addon = stage / "addons/launch_check"
    addon.mkdir(parents=True)
    for name in ("plugin.cfg", "plugin.gd"):
        shutil.copy2(fixtures / name, addon / name)
    shutil.copy2(fixtures / "launch_probe.gd", stage / "launch_probe.gd")
    scene_path = stage / "scenes/main.tscn"
    scene = scene_path.read_text().replace("load_steps=2", "load_steps=3")
    scene = scene.replace('[node name="LanXiJi"',
                          '[ext_resource type="Script" path="res://launch_probe.gd" id="2"]\n\n[node name="LanXiJi"')
    scene += '\n[node name="LaunchProbe" type="Node" parent="."]\nscript = ExtResource("2")\n'
    scene_path.write_text(scene)
    results = stage / "results"
    results.mkdir()
    (results / ".gdignore").touch()
    commands = [
        [args.godot, "--headless", "--editor", "--path", str(stage), "--import"],
        [args.godot, "--editor", "--path", str(stage), "--", "--verify-editor-play"],
    ]
    try:
        for label, command in zip(("import", "editor-play"), commands):
            result = subprocess.run(command, capture_output=True, text=True, timeout=90)
            (results / (label + ".log")).write_text(result.stdout + result.stderr)
            if result.returncode:
                raise RuntimeError(f"{label} failed; see {results / (label + '.log')}")
        summary = (results / "complete.txt").read_text()
        if not summary.endswith("failures=0"):
            raise RuntimeError(summary)
        print(summary)
    finally:
        destination = source / "builds/editor-launch"
        shutil.copytree(results, destination, dirs_exist_ok=True)
        print(f"Evidence: {destination}\nIsolated project: {stage}")


if __name__ == "__main__":
    main()
