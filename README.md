# AHOGE LEGEND

ホロライブメンバーの頭頂部とアホ毛を主役にした、1対1オンライン対戦ゲームの開発リポジトリです。

現在は本番実装の最初の縦切りとして、Godot上でロング型とショート投擲型の仮キャラクターを使ったローカル対戦基盤を構築しています。

## 開発環境

- Godot 4.7.2 stable
- クライアント: GDScript
- オンライン基盤: Nakama
- DB: PostgreSQL
- Nakamaサーバー: TypeScript
- ローカルサーバー: Docker Compose
- 本番サーバー: AWS 東京リージョン
- 配布予定: Steam

## 現在のローカル縦切り

- LONG_TEST / SHORT_TEST
- 85秒ラウンド
- 5ヒットでラウンド取得
- BO3 / 2ラウンド先取
- 同点時間切れからOvertime
- 攻撃／チャージ／パリィ／回避の状態遷移基盤

画面は機能確認を優先した仮UIです。

## 起動

Godot 4.7.2 stableでリポジトリ直下の `project.godot` を開いて実行します。

```bash
godot --path .
```

## 自動試験

```bash
godot --headless --path . --script res://tests/run_all.gd
```

## ローカル検証操作

- Player 1: 左クリック = Attack / Charge、右クリック = Parry / Dodge
- Player 2: Q = Attack / Charge、E = Parry / Dodge
- Debug hit: 1 = Player 1へ有効ヒット加算、2 = Player 2へ有効ヒット加算

Debug hitはラウンド・BO3・Overtimeの縦切り確認用であり、本番操作ではありません。

## 設計正本

- `docs/BASIC_DESIGN.md`
- `docs/DETAILED_DESIGN.md`
- `docs/SCREEN_DESIGN.md`
- `AGENTS.md`
