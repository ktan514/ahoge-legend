# AHOGE LEGEND

ホロライブメンバーの頭頂部とアホ毛を主役にした、1対1オンライン対戦ゲームの開発リポジトリです。

現在はGodot上のローカル戦闘基盤に加え、Nakama + PostgreSQLによるオンライン基盤を段階的に構築しています。

## 開発環境

- Godot 4.7.2 stable
- クライアント: GDScript
- Nakama: 3.41.0
- Nakama Common / nakama-runtime: 1.48.0
- Nakama Godot SDK: 3.4.0
- PostgreSQL: 16.8-alpine
- Nakamaサーバー: TypeScript
- ローカルサーバー: Docker Compose
- 本番サーバー: AWS 東京リージョン
- 配布予定: Steam

## ローカル戦闘

現在のローカル縦切りでは次を確認できます。

- LONG_TEST / SHORT_TEST
- 85秒ラウンド
- 5ヒットでラウンド取得
- BO3 / 2ラウンド先取
- 同点時間切れからOvertime
- 通常攻撃 / Charge
- Parry / Just Parry
- Dodge / Just Dodge
- Attack Clash
- SHORT_TESTのdetach / regrow
- 頭部→アホ毛二次動作の仮モーション

画面は機能確認を優先した仮UIです。

Godot起動:

```bash
godot --path .
```

Godot自動試験:

```bash
godot --headless --path . --script res://tests/run_all.gd
```

ローカル操作:

- Player 1: 左クリック = Attack / Charge、右クリック = Parry / Dodge
- Player 2: Q = Attack / Charge、E = Parry / Dodge

## ローカルオンライン基盤

Dockerが起動している状態で実行します。

起動:

```bash
./scripts/server-up.sh
```

疎通確認:

```bash
./scripts/server-health.sh
```

正常時は `ahoge_health` RPCが `status: ok` を返します。

停止:

```bash
./scripts/server-down.sh
```

Nakama API:

```text
http://127.0.0.1:7350
```

Nakama Console:

```text
http://127.0.0.1:7351
```

PostgreSQLはhostの5432へ公開せず、Docker Compose内部ネットワークでNakamaから接続する。
そのため、PC上ですでに別のPostgreSQLが5432を使用していても競合しない。

ローカルConsoleはNakamaの開発用既定認証を使用します。本番環境のcredentialとは共有しません。

## Nakama TypeScript Runtime

```bash
cd server/nakama
npm install
npm run type-check
npm run build
```

生成される `server/nakama/build/` と `node_modules/` はcommitしません。

## Godot → Nakamaローカル認証

Nakama起動後に、GodotクライアントからDevice認証できることを確認します。

```bash
./scripts/server-up.sh
./scripts/client-online-smoke.sh
```

成功時:

```text
AHOGE LEGEND online smoke: PASS
```

開発用Device IDは `user://ahoge_device_id.txt` に保存して再利用します。
raw auth tokenは通常ログへ出力しません。

現在のDevice認証はローカル開発用です。Steam公開時の正式認証は後続Issueで実装します。

SDKは `heroiclabs/nakama-godot` v3.4.0を `addons/com.heroiclabs.nakama/` へvendorしています。

## 設計正本

- `docs/BASIC_DESIGN.md`
- `docs/DETAILED_DESIGN.md`
- `docs/SCREEN_DESIGN.md`
- `AGENTS.md`
