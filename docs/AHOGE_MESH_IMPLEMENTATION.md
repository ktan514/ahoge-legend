# 固定アホ毛メッシュ実装・検証記録

関連: #102 / PR #105 / `AHOGE_MESH_DEFORMATION_DESIGN.md`

## 実装順序

承認済み設計の順に、現行素材の識別、固定メッシュと形状キー、全体運動への接続、描画検証を実施する。通常GameFlow・サーバー判定は変更しない。

## 素材監査

`python tools/ahoge_mesh/inspect_source.py` は現行LONG素材の寸法、alpha範囲、SHA-256、Git blob SHAを保存する。縮小輪郭と元画像をCI artifactへ保存し、旧HTML素材との取り違えを防ぐ。製品素材の変更・生成は行わない。

`Ahoge mesh verification` は素材とメッシュの制作・描画検証専用CIである。素材監査の成功だけをメッシュ完成やHuman Verification成功とみなさない。メッシュ検査・実描画検査は実装に合わせて追加する。

## 現在の到達点

- 素材監査と検証資料保存の導線を追加。
- 固定メッシュの製品接続・形状補間・実描画検証は未完了。
- Human Verification未実施。PRはマージしない。
