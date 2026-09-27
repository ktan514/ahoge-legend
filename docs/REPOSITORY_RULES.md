# リポジトリ固有規約

この文書には、このリポジトリにだけ必要な追加規約を記載する。

共通規約は `GITHUB_OPERATION_RULES.md` を参照し、ここへ複製しない。

## 実行環境

AHOGE LEGENDの開発・公開環境は次とする。

- ゲームエンジン: Godot 4.7.2 stable
- クライアント実装言語: GDScript
- Nakamaサーバー実装言語: TypeScript
- 開発IDE: Godot Editor + VS Code
- オンライン基盤: Nakama 3.41.0
- Nakama Common / nakama-runtime: 1.48.0
- Nakama Godot SDK: 3.4.0
- DB: PostgreSQL 16.8-alpine
- ローカルサーバー: Docker Compose
- 本番サーバー: AWS 東京リージョン
- 配布: Steam
- 必須対象OS: Windows 64bit
- macOS: 対応可能であれば対象とする

Godotは4.7.2 stableで初期化し、バージョン更新は専用Issueと検証を経て行う。

ローカル開発ではNakama 3.41.0とPostgreSQL 16.8-alpineをDocker Composeで起動する。Nakama TypeScript Runtimeはnakama-runtime 1.48.0と組み合わせ、TypeScriptをES5へcompileする。

オンライン対戦の勝敗・85秒タイマー・有効ヒット・防御結果・攻撃相殺・ラウンド／マッチ勝敗・ランキング更新は、Nakama側のサーバー権威で確定する。

見た目の頭部・アホ毛モーションおよび制御付き擬似物理はGodotクライアント側で扱い、サーバーの勝敗判定とは分離する。

## テスト・検証コマンド

Godot 4.7.2 stableを使用する。

プロジェクト起動:

```bash
godot --path .
```

fresh checkout / SDK更新後のGodot import:

```bash
./scripts/godot-import.sh
```

headlessでプロジェクト読込確認:

```bash
godot --headless --path . --quit
```

ローカル自動試験:

```bash
godot --headless --path . --script res://tests/run_all.gd
```

Godot → Nakama認証smoke test:

```bash
./scripts/client-online-smoke.sh
```

Godot → Nakama Realtime Socket smoke test:

```bash
./scripts/client-realtime-smoke.sh
```

2-client Ranked Matchmaker smoke test:

```bash
./scripts/client-matchmaker-smoke.sh
```

オンライン基盤起動:

```bash
./scripts/server-up.sh
```

オンライン基盤疎通確認:

```bash
./scripts/server-health.sh
```

オンライン基盤停止:

```bash
./scripts/server-down.sh
```

Nakama TypeScript Runtime:

```bash
cd server/nakama
npm install
npm run type-check
npm run build
```

コマンドを実行していない場合はPASS扱いしない。

## 保護対象branch

- `main`

必要に応じて追加する。

## ディレクトリ固有ルール

- `src/config/`: 調整可能な戦闘値を一元管理する。Sceneや状態クラスへ暫定値を重複記載しない。
- `src/domain/`: ゲームルール上の状態・定義を置き、UIへ依存させない。
- `src/services/`: ラウンド／マッチ等の進行制御を置く。
- `src/ui/`: Godot画面と表示・入力の接着を担当し、勝敗ルールそのものを持たせない。
- `tests/`: headless実行できる回帰試験を置く。
- `server/nakama/`: Nakama TypeScript Runtimeとローカル設定を置く。Godot UIやクライアント表示へ依存させない。
- `scripts/server-*.sh`: Docker Composeの起動・停止・疎通確認だけを担当し、本番credentialを含めない。
- `addons/com.heroiclabs.nakama/`: 公式Nakama Godot SDK 3.4.0をvendorし、独自改変しない。
- `src/online/`: Godotクライアント側のNakama接続・認証・Session管理を置き、UIや戦闘ルールへ依存させない。
- `scripts/client-online-smoke.sh`: ローカルNakama起動確認後にGodot headless認証smoke testを実行する。
- `scripts/client-realtime-smoke.sh`: 認証後にNakama Realtime Socketへ接続し、接続状態と明示切断を検証する。
- `scripts/client-matchmaker-smoke.sh`: 2クライアントをDevice認証・Realtime接続し、Matchmaker成立から同一authoritative matchへのjoinまで検証する。
- `server/nakama/src/ranked_match.ts`: 2人用authoritative match骨格とMatchmaker Matched hookを定義し、戦闘ルールそのものは後続Issueで追加する。

## アセット管理

- 配信から切り出した音声を扱う場合、音声ファイルだけを単独で追加せず、出典と使用可否状態を追跡できる情報を保持する。
- 使用可否状態が未確認の素材は、公開ビルドへ含めない。
- 公式提供素材・第三者ライセンス素材は、提供元またはライセンス条件を記録する。
- 権利確認状態をAIが推測して変更しない。

## その他

- Steam、Nakama、PostgreSQL、AWSのcredentialやsecretをリポジトリへcommitしない。
- ローカル固有設定は秘密情報を含まないテンプレートと実値を分離する。
- 本番インフラの具体的なAWSリソース構成は専用Issueと設計変更を経て決定する。
