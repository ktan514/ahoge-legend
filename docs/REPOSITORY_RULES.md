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

2-client authoritative combat input smoke test:

```bash
./scripts/client-combat-input-smoke.sh
```

2-client authoritative attack state / ContactEvent smoke test:

```bash
./scripts/client-attack-state-smoke.sh
```

2-client authoritative Defense state smoke test:

```bash
./scripts/client-defense-state-smoke.sh
```

2-client authoritative Defense result smoke test:

```bash
./scripts/client-defense-result-smoke.sh
```

2-client authoritative Contact outcome smoke test:

```bash
./scripts/client-contact-outcome-smoke.sh
```

2-client authoritative Stagger smoke test:

```bash
./scripts/client-stagger-smoke.sh
```

2-client authoritative SHORT state smoke test:

```bash
./scripts/client-short-state-smoke.sh
```

工程1 2-client combat integration smoke test:

```bash
./scripts/client-combat-integration-smoke.sh
```

2-client authoritative Hit count smoke test:

```bash
./scripts/client-hit-count-smoke.sh
```

2-client authoritative 85 second timer smoke test:

```bash
./scripts/client-round-timer-smoke.sh
```

2-client authoritative 5 Hit round win smoke test:

```bash
./scripts/client-hit-limit-smoke.sh
```

2-client authoritative timeout winner smoke test:

```bash
./scripts/client-timeout-winner-smoke.sh
```

2-client authoritative Overtime smoke test:

```bash
./scripts/client-overtime-smoke.sh
```

2-client authoritative Round Result smoke test:

```bash
./scripts/client-round-result-smoke.sh
```

2-client authoritative BO3 full match smoke test:

```bash
./scripts/client-bo3-smoke.sh
```

2-client authoritative Match Result smoke test:

```bash
./scripts/client-match-result-smoke.sh
```

M1 authoritative Battle UI integration smoke test:

```bash
./scripts/client-m1-battle-smoke.sh
```

M1 Godot実ウィンドウ起動:

```bash
./scripts/client-m1-battle.sh
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

## CI実行区分

`Online foundation` は、開発中のPR反復速度と本番相当の回帰保証を分離する。

### PR fast regression

Pull Request更新時は、通常の認証・Realtime・Matchmaker・combat・Round / BO3 / Match Result・M1 headless smokeを実行する。ただし、85秒を実時間で待つ次の3本はPR fastから除外する。

- `client-round-timer-smoke.sh`
- `client-timeout-winner-smoke.sh`
- `client-overtime-smoke.sh`

85秒というproduction定数、2550tick換算、timeout / Overtimeのルール自体はheadless unit / protocol testで回帰する。

PR fastではGodot importをjob冒頭で1回だけ実行し、各client smokeからの重複importを省略する。

同一PRへ新しいcommitがpushされた場合、旧HEAD向けの実行はcancelし、最新HEADを優先する。

### full regression

`main` pushおよび手動 `workflow_dispatch` では、PR fast項目に加えて上記3本も実行し、productionの85秒を実時間で通す。

full regressionを実行していない状態で「85秒authoritative E2E PASS」と記録しない。

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
- `server/nakama/src/combat_config.ts`: server authoritative戦闘の暫定時間値と30Hz tick換算・補間を一元管理する。
- `server/nakama/src/ranked_match.ts`: 2人用authoritative match、Matchmaker Matched hook、character_id保持、戦闘入力のsequence/tick検証、攻撃状態遷移、Defense state、ContactEvent、DefenseResult、AttackClash、Hit、Stagger、SHORT detach / regrow、現在ラウンドHit数、85秒timer、5 Hitラウンド終了、timeout Hit数比較、Overtime次Hit終了、Round Result、2本先取BO3、3/2/1/GO Round Countdown、Round reset、Match Result通知を定義する。
- `scripts/client-combat-input-smoke.sh`: 2クライアントでauthoritative matchへjoinし、正常入力の確定通知とduplicate / out-of-order / same-tick rejectionを検証する。
- `scripts/client-attack-state-smoke.sh`: 2クライアントで同じauthoritative攻撃状態遷移とContactEventを受信できることを検証する。
- `scripts/client-defense-state-smoke.sh`: 2クライアントでPARRY / DODGE状態、攻撃キャンセル、Defense終了後復帰、Cooldown一時停止・再開を検証する。
- `scripts/client-defense-result-smoke.sh`: Contact到達時のNONE / PARRY / JUST_PARRY確定と、両クライアントのDefenseResult一致を検証する。DODGE / JUST_DODGEの実運用経路は `scripts/client-short-state-smoke.sh` で検証する。
- `scripts/client-contact-outcome-smoke.sh`: 2クライアントでHit、DefenseによるHit抑止、AttackClash確定と両client結果一致を検証する。
- `scripts/client-stagger-smoke.sh`: Just DefenseとAttackClashからのSTAGGER、14tick継続、入力抑止、IDLE復帰、両client状態一致を検証する。
- `scripts/client-short-state-smoke.sh`: SHORT_TESTのcharacter_id引き渡し、detach、DODGE、JUST_DODGE、18tick Regrow、PARRY復帰、両client状態一致を検証する。
- `scripts/client-combat-integration-smoke.sh`: 工程1の攻撃・Defense cancel・PARRY / DODGE / Just・Hit・Clash・Stagger・SHORT detach / Regrowを同一match内で連続実行し、両clientのイベント列・状態列一致を検証する。
- `scripts/client-hit-count-smoke.sh`: 初期0、Hit加算、Defense / Clash非加算、複数Hit累積、両clientのHit count一致を検証する。
- `scripts/client-round-timer-smoke.sh`: 85開始、1秒ごとの整数減算、0到達、2550tick経過、0後停止、両clientのtimer event列一致を検証する。
- `scripts/client-hit-limit-smoke.sh`: 1〜4 Hit継続、5 Hit目のcount=5、終了tickの両者ROUND_LOCKEDとRound Resultを検証する。次Round lifecycleはBO3 smokeで検証する。
- `scripts/client-timeout-winner-smoke.sh`: 1-0のHit数で85秒を完走し、timer 0、終了tickの両者ROUND_LOCKED、TIMEOUT Round Result、両client event一致を検証する。次Round lifecycleはBO3 smokeで検証する。
- `scripts/client-overtime-smoke.sh`: 0-0 timeout、次tick Overtime開始、timer 0維持、PARRY / Clash継続、次の有効Hitでcount更新後ROUND_LOCKED、両client一致を検証する。
- `scripts/client-round-result-smoke.sh`: HIT_LIMIT Round Resultのround番号、winner / loser、Hit数、finish cause、server tick、1回限り通知、両client一致を検証する。TIMEOUT / OVERTIME_HITは既存各smokeで同契約を回帰する。
- `scripts/client-bo3-smoke.sh`: 1-0→1-1→2-1の最大3Roundを通し、各Roundの3/2/1/GO Countdown、Countdown開始時のHit数0 / timer85 / ROUND_LOCKED、GOと同tickのRound Started / IDLE、score、input sequence継続、2勝後のmatch停止、Match Result、両client一致を検証する。
- `scripts/client-match-result-smoke.sh`: 1勝・1-1ではMatch Result非通知、2勝確定時のwinner / loser / final score / final round / server tick、1回限り通知、終了後停止を検証する。
- `src/ui/battle_m1_debug.gd`: M1専用にP1/P2の2つのNakama clientを同一Godot processで成立させ、authoritative eventをUI-10へ反映する。勝敗ルールは持たない。
- `scripts/client-m1-battle-smoke.sh`: M1 Battle Sceneから2-client authoritative matchへjoinし、初期timer / Hit snapshotをHUD用stateへ受信できることをheadlessで検証する。
- `scripts/client-m1-battle.sh`: M1 Human Verification用に `--m1-battle` でGodot実ウィンドウを起動する。

## アセット管理

- 配信から切り出した音声を扱う場合、音声ファイルだけを単独で追加せず、出典と使用可否状態を追跡できる情報を保持する。
- 使用可否状態が未確認の素材は、公開ビルドへ含めない。
- 公式提供素材・第三者ライセンス素材は、提供元またはライセンス条件を記録する。
- 権利確認状態をAIが推測して変更しない。

## その他

- Steam、Nakama、PostgreSQL、AWSのcredentialやsecretをリポジトリへcommitしない。
- ローカル固有設定は秘密情報を含まないテンプレートと実値を分離する。
- 本番インフラの具体的なAWSリソース構成は専用Issueと設計変更を経て決定する。
