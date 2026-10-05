"""同じHEADとGodotで描画差を再現するための許可リスト型アーカイブ。"""
from pathlib import Path, PurePosixPath
import subprocess
import tarfile

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "artifacts" / "motion-reproduction"
PREFIXES = ("src/", "scenes/", "assets/", "addons/", "tests/", "tools/ahoge_mesh/", "docs/")
FILES = {"project.godot", ".godot-version", "AGENTS.md", "README.md", "scripts/godot-import.sh", "scripts/godot-strict.sh"}


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    engine = ROOT / ".ci-bin/godot"
    if not engine.is_file():
        raise RuntimeError("検証用Godotがありません")
    tracked = subprocess.check_output(["git", "ls-files", "-z"], cwd=ROOT).decode().split("\0")
    sha = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT).decode().strip()
    (OUT / "tested_commit.txt").write_text(sha + "\n", encoding="utf-8")
    copyright_text = subprocess.check_output([str(engine), "--headless", "--copyright"], cwd=ROOT, stderr=subprocess.STDOUT)
    (OUT / "GODOT_COPYRIGHT.txt").write_bytes(copyright_text)
    with tarfile.open(OUT / "client-reproduction.tar.gz", "w:gz") as archive:
        for name in tracked:
            if not name or not (name in FILES or name.startswith(PREFIXES)):
                continue
            parts = PurePosixPath(name).parts
            if any(part in {".git", ".env"} or part.startswith(".env.") for part in parts):
                continue
            source = ROOT / name
            if source.is_symlink() or not source.is_file():
                continue
            archive.add(source, arcname="client/" + name, recursive=False)
        archive.add(engine, arcname="client/bin/godot", recursive=False)
        archive.add(OUT / "tested_commit.txt", arcname="client/tested_commit.txt", recursive=False)
        archive.add(OUT / "GODOT_COPYRIGHT.txt", arcname="client/GODOT_COPYRIGHT.txt", recursive=False)
    print("同一HEADのクライアント描画再現資料を保存しました: " + sha)


if __name__ == "__main__":
    main()
