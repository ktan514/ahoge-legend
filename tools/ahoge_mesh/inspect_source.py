"""現行アホ毛素材の識別と輪郭確認資料を保存する。製品画像は変更しない。"""
from __future__ import annotations
import argparse
import base64
import hashlib
import json
from pathlib import Path
from PIL import Image


def inspect(source: Path, output: Path) -> dict:
    raw = source.read_bytes()
    image = Image.open(source).convert("RGBA")
    alpha = image.getchannel("A")
    bounds = alpha.getbbox()
    if bounds is None:
        raise ValueError("素材が全透明です")
    output.mkdir(parents=True, exist_ok=True)
    report = {
        "source": source.as_posix(), "size": list(image.size),
        "sha256": hashlib.sha256(raw).hexdigest(),
        "git_blob_sha": hashlib.sha1(b"blob " + str(len(raw)).encode() + b"\0" + raw).hexdigest(),
        "alpha_bounds": list(bounds),
    }
    (output / "source.png").write_bytes(raw)
    thumb = image.copy()
    thumb.thumbnail((160, 160))
    thumb.save(output / "thumbnail.png")
    # 制作中に遠隔CIの結果を小さい輪郭画像として確認できるようにする。
    silhouette = alpha.resize((160, 160), Image.Resampling.LANCZOS)
    silhouette.save(output / "silhouette.png")
    report["silhouette_png_base64"] = base64.b64encode((output / "silhouette.png").read_bytes()).decode()
    (output / "source_report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, ensure_ascii=False))
    return report


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=Path("assets/characters/prototype/charactor_01/ahoge.png"))
    parser.add_argument("--output", type=Path, default=Path("artifacts/ahoge-mesh/source"))
    args = parser.parse_args()
    inspect(args.source, args.output)
