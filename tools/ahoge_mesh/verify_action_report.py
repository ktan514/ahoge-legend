#!/usr/bin/env python3
"""三動作の実行結果を照合する。空試験や中断した実行を成功扱いしない。"""
from __future__ import annotations

import json
import math
from pathlib import Path

from shapely.geometry import Polygon

ROOT = Path("artifacts/ahoge-mesh")


def read(relative: str) -> dict:
    value = json.loads((ROOT / relative).read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise AssertionError(f"結果形式が不正: {relative}")
    return value


def verify_velocities(cases: list[dict]) -> list[dict]:
    results = []
    for case in cases:
        parts = case["label"].split("_")
        if int(parts[1]) != 120:
            continue
        facing = 1.0 if int(parts[2]) == 0 else -1.0
        trace = case["trace"]
        assert len(trace) > 4, "速度検査用のframe不足"
        # 現行仕様のcontact_ratio=0.70。試験が記録した実STRIKE時間を使う。
        contact_time = float(trace[-1]["time"]) * 0.70
        peaks, speeds = {}, {}
        for name in ("root", "middle", "tip"):
            measured = []
            for first, second in zip(trace, trace[1:]):
                t0, t1 = float(first["time"]), float(second["time"])
                assert t1 > t0, "時系列が逆転または重複"
                if t1 > contact_time + 1e-6:
                    continue
                speed = (float(second[name][0]) - float(first[name][0])) * facing / (t1 - t0)
                assert math.isfinite(speed), "速度が有限値ではない"
                measured.append((speed, t1))
            assert measured, "接触前の速度が未検査"
            speeds[name], peaks[name] = max(measured)
        assert peaks["root"] < peaks["middle"] < peaks["tip"], f"ムチの速度ピーク順序が不正: {case['label']} {peaks}"
        assert speeds["tip"] > max(speeds["root"], speeds["middle"]), f"毛先が最速ではない: {case['label']} {speeds}"
        results.append({"label": case["label"], "peak_times_seconds": peaks, "peak_forward_speed_px_s": speeds})
    assert len(results) == 8, "速度検査の条件数が8ではない"
    return results


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
    velocities = verify_velocities(actions["cases"])
    result = {"status": "PASS", "cases": summaries, "boundary_samples": len(samples), "velocity_cases": velocities, "continuous_proof": False}
    (ROOT / "actions/verification.json").write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    print("三動作の実行結果・外周・速度順序検査: PASS", summaries, "形状数", len(samples), "速度条件", len(velocities))


if __name__ == "__main__":
    main()
