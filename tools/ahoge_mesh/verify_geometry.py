"""固定面の補間全区間を検査する。離散サンプルだけで途中形状を保証しない。"""
from __future__ import annotations
import argparse, json, math
from collections import Counter
from pathlib import Path

EPS = 1e-5


def sub(a, b):
    return (a[0] - b[0], a[1] - b[1])


def cross(a, b):
    return a[0] * b[1] - a[1] * b[0]


def lerp(a, b, t):
    return (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t)


def orient(a, b, c):
    return cross(sub(b, a), sub(c, a))


def polynomial(a, b, ids):
    i, j, k = ids
    e = sub(a[j], a[i]); f = sub(a[k], a[i])
    de = sub(sub(b[j], b[i]), e); df = sub(sub(b[k], b[i]), f)
    return (cross(e, f), cross(e, df) + cross(de, f), cross(de, df))


def roots(p):
    c, b, a = p
    if abs(a) < 1e-10:
        return [] if abs(b) < 1e-10 else [-c / b]
    discriminant = b * b - 4 * a * c
    if discriminant < -1e-8:
        return []
    value = math.sqrt(max(0.0, discriminant))
    q = -0.5 * (b + math.copysign(value, b))
    return [-b / (2 * a)] if abs(q) < 1e-14 else [q / a, c / q]


def on_segment(p, a, b):
    return abs(orient(a, b, p)) <= EPS and all(min(a[j], b[j]) - EPS <= p[j] <= max(a[j], b[j]) + EPS for j in [0, 1])


def intersects(a, b, c, d):
    x = orient(a, b, c); y = orient(a, b, d)
    z = orient(c, d, a); w = orient(c, d, b)
    if x * y < 0 and z * w < 0:
        return True
    return on_segment(c, a, b) or on_segment(d, a, b) or on_segment(a, c, d) or on_segment(b, c, d)


def swept_bounds(a, b, edge):
    points = [a[edge[0]], a[edge[1]], b[edge[0]], b[edge[1]]]
    return tuple(min(x[j] for x in points) for j in [0, 1]) + tuple(max(x[j] for x in points) for j in [0, 1])


def disjoint(x, y):
    return x[2] < y[0] - EPS or y[2] < x[0] - EPS or x[3] < y[1] - EPS or y[3] < x[1] - EPS


def moving_edges_intersect(a, b, e, f):
    if disjoint(swept_bounds(a, b, e), swept_bounds(a, b, f)):
        return False
    times = [0.0, 1.0]
    for triple in [(e[0], e[1], f[0]), (e[0], e[1], f[1]), (f[0], f[1], e[0]), (f[0], f[1], e[1])]:
        times += [t for t in roots(polynomial(a, b, triple)) if 0 < t < 1]
    # 全区間で同一直線上にある辺でも、端点が追い越す時刻を取りこぼさない。
    for i in e:
        for j in f:
            for axis in [0, 1]:
                c = a[i][axis] - a[j][axis]
                velocity = (b[i][axis] - a[i][axis]) - (b[j][axis] - a[j][axis])
                if abs(velocity) > 1e-10:
                    t = -c / velocity
                    if 0 < t < 1:
                        times.append(t)
    times = sorted(set(times))
    probes = times + [(s + t) * 0.5 for s, t in zip(times, times[1:])]
    for t in probes:
        points = [lerp(a[i], b[i], t) for i in (*e, *f)]
        if intersects(*points):
            return True
    return False


def verify(data):
    rest = data['rest_vertices_px']; keys = data['shape_key_vertices']; flat = data['triangle_indices']
    triangles = list(zip(flat[0::3], flat[1::3], flat[2::3]))
    assert all(math.isfinite(c) for key in keys for p in key for c in p)
    assert all(len(key) == len(rest) for key in keys)
    edges = Counter(tuple(sorted(e)) for a, b, c in triangles for e in [(a, b), (b, c), (c, a)])
    assert all(count in [1, 2] for count in edges.values()), '面の接続が非manifoldです'
    boundary = [edge for edge, count in edges.items() if count == 1]
    assert len(rest) - len(edges) + len(triangles) == 1, '面の接続に穴または余分な面があります'
    degree = Counter(i for edge in boundary for i in edge)
    assert all(value == 2 for value in degree.values()), '境界が閉じていません'
    pending = set(degree); todo = [pending.pop()]
    while todo:
        vertex = todo.pop()
        for edge in boundary:
            if vertex in edge:
                other = edge[0] if edge[1] == vertex else edge[1]
                if other in pending:
                    pending.remove(other); todo.append(other)
    assert not pending, '境界が複数に分離しています'
    minimum = math.inf; interval_checks = 0; edge_checks = 0
    for a, b in zip(keys, keys[1:]):
        for triangle in triangles:
            reference = orient(*(rest[i] for i in triangle))
            assert abs(reference) > EPS, '待機形状の退化面'
            p = polynomial(a, b, triangle); direction = 1 if reference > 0 else -1
            tests = [0, 1]
            if abs(p[2]) > 1e-10:
                extreme = -p[1] / (2 * p[2])
                if 0 < extreme < 1:
                    tests.append(extreme)
            value = min(direction * (p[0] + p[1] * t + p[2] * t * t) for t in tests)
            assert value > EPS, '補間途中の反転または退化'
            minimum = min(minimum, value / abs(reference)); interval_checks += 1
        for index, e in enumerate(boundary):
            for f in boundary[index + 1:]:
                if set(e) & set(f):
                    continue
                assert not moving_edges_intersect(a, b, e, f), f'補間途中の境界交差: {e} {f}'
                edge_checks += 1
    result = {'vertices': len(rest), 'triangles': len(triangles), 'shape_keys': len(keys), 'area_interval_checks': interval_checks, 'boundary_interval_checks': edge_checks, 'minimum_area_ratio': minimum}
    print('Ahoge continuous geometry: PASS ' + json.dumps(result))
    return result


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('path', nargs='?', type=Path, default=Path('artifacts/ahoge-mesh/profile_geometry.json'))
    args = parser.parse_args()
    report = verify(json.loads(args.path.read_text(encoding='utf-8')))
    args.path.with_name('continuous_geometry_report.json').write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
