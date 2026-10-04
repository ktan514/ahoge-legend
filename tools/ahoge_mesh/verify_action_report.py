#!/usr/bin/env python3
"""三動作の実行結果を照合する。空試験や中断した実行を成功扱いしない。"""
from __future__ import annotations

import json
from pathlib import Path

from shapely.geometry import Polygon

ROOT = Path("artifacts/ahoge-mesh")


def read(relative: str) -> dict:
    value = json.loads((ROOT / relative).read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise AssertionError(f"結果形式が不正: {relative}")
    return value


def main() -> None:
    summaries = {}
    for path, count in [("contact/report.json", 48), ("parry/report.json", 48), ("actions/report.json", 24)]:
        report = read(path)
        assert report.get("status") == "PASS", f"試験が不合格: {path}"
        assert len(report.get("cases", [])) == count, f"条件数が不足: {path}"
        assert not report.get("failures"), f"失敗が残る: {path}"
        summaries[path] = count
    actions = read("actions/report.json")
    assert actions["checks"] > 1000 and actions["geometry_frames"] > 100
    contact = read("contact/report.json")
    for case in contact["cases"]:
        # フィールド名が異なる結果も誤って合格にしない。
        width = case.get("section_width", {})
        assert width.get("sampled_sections", 0) > 0, f"幅検査が未実施: {case.get('label')}"
    geometry = read("actions/geometry_samples.json")
    boundary = geometry["boundary"]
    samples = geometry["samples"]
    assert len(samples) >= 10, "外周検査用の実描画形状が不足"
    for sample in samples:
        points = sample["vertices"]
        polygon = Polygon([points[int(i)] for i in boundary])
        assert polygon.is_valid and polygon.area > 0, f"三動作の外周が自己交差: {sample['label']} state={sample['state']}"
    result = {"status": "PASS", "cases": summaries, "boundary_samples": len(samples), "continuous_proof": False}
    (ROOT / "actions/verification.json").write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    print("三動作の実行結果・外周検査: PASS", summaries, "形状数", len(samples))


if __name__ == "__main__":
    main()
