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

fresh checkout / SDK更新後の初回import:

```bash
./scripts/godot-import.sh
```

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
`client-online-smoke.sh` は実行前にGodot importも行うため、fresh checkoutでもそのまま実行できます。

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

## Godot → Nakama Realtime Socket

Device認証済みSessionからRealtime Socketへ接続できることを確認します。

```bash
./scripts/server-up.sh
./scripts/client-realtime-smoke.sh
```

成功時:

```text
AHOGE LEGEND realtime smoke: PASS
```

この段階では接続・接続状態確認・明示切断までを対象とし、Matchmakerや対戦同期は後続Issueで実装します。
Socket接続時もraw auth tokenはログへ出力しません。

## Ranked Matchmaker → authoritative match

2クライアントがRanked Matchmakerで組み合わされ、同じauthoritative matchへjoinできることを確認します。

```bash
./scripts/server-up.sh
./scripts/client-matchmaker-smoke.sh
```

成功時:

```text
AHOGE LEGEND matchmaker smoke: PASS
```

初期検索は2人固定、`mode=ranked`、Rating ±100です。
10秒ごとの検索幅拡大、勝敗処理は後続Issueで実装します。

## Authoritative combat input

join済みauthoritative matchへ戦闘入力を送り、serverがsequence / tickを検証して受理入力だけを両クライアントへ返すことを確認します。

```bash
./scripts/server-up.sh
./scripts/client-combat-input-smoke.sh
```

成功時:

```text
AHOGE LEGEND combat input smoke: PASS
```

初期入力は `ATTACK_PRESS / ATTACK_RELEASE / DEFEND` の3種類です。
入力受付に加え、ATTACK_PRESS / ATTACK_RELEASEはserver authoritativeな攻撃状態へ接続されています。

## Authoritative attack state / ContactEvent

Nakama 30Hz tickで `IDLE → CHARGING → WINDUP → STRIKE → COOLDOWN → IDLE` を進行し、Strike中の論理接触時刻でContactEventを生成します。

```bash
./scripts/server-up.sh
./scripts/client-attack-state-smoke.sh
```

成功時:

```text
AHOGE LEGEND attack state smoke: PASS
```

戦闘時間はserver側設定へ集約し、既存Godot CombatConfigと同じ暫定値を使用します。
Contact到達に加え、DEFENDはserver authoritativeなPARRY / DODGE stateへ接続されています。

## Authoritative Defense state

DEFEND入力をNakama側でPARRY / DODGEへ変換し、攻撃中Defense cancelとCooldown一時停止・再開をserver tickで管理します。

```bash
./scripts/server-up.sh
./scripts/client-defense-state-smoke.sh
```

成功時:

```text
AHOGE LEGEND defense state smoke: PASS
```

PARRYは0.18秒、DODGEは0.22秒、Just受付は0.07秒の暫定値を30Hz tickへ量子化して保持します。
この段階ではDefense stateまでをserver authoritativeとし、Contact到達時のParry / Dodge / Just結果、Clash、Hitは後続Issueで確定します。

## Authoritative Defense result

ContactEvent到達時のserver tickで相手のDefense stateを参照し、`NONE / PARRY / JUST_PARRY / DODGE / JUST_DODGE` を確定して両クライアントへ通知します。

```bash
./scripts/server-up.sh
./scripts/client-defense-result-smoke.sh
```

成功時:

```text
AHOGE LEGEND defense result smoke: PASS
```

Defense active / Justの終了tickは排他的境界として扱います。Attack Clash / Hit / Staggerとの接続は後続の各節で説明します。

## Authoritative Contact outcome

両者のContact予定tick差がAttackClash許容幅内なら遅い側Contactまで確定を待ってClashとし、それ以外はDefenseResultがNONEのContactだけをHitとして確定します。

```bash
./scripts/server-up.sh
./scripts/client-contact-outcome-smoke.sh
```

成功時:

```text
AHOGE LEGEND contact outcome smoke: PASS
```

AttackClash許容差0.067秒は30Hzで3tickへ量子化します。Hit数加算は後続Issueで接続します。

## Authoritative Stagger

Just Parry / Just Dodge成功時は攻撃側、AttackClash時は両者をserver authoritativeなSTAGGERへ遷移させます。Stagger 0.45秒は30Hzで14tickへ量子化し、終了後はIDLEへ復帰します。

```bash
./scripts/server-up.sh
./scripts/client-stagger-smoke.sh
```

成功時:

```text
AHOGE LEGEND stagger smoke: PASS
```

Stagger中はAttack / Defenseによる状態遷移を行いません。見た目のStaggerモーション仕上げは後続の画面・演出工程で行います。

## Authoritative SHORT detach / regrow

Ranked Matchmakerへ選択済み `character_id` を渡し、SHORT_TESTのTHROW攻撃はSTRIKE開始tickで `ahoge_available=false` へdetachします。0.60秒は30Hzで18tickへ量子化し、action stateと独立してregrowします。

```bash
./scripts/server-up.sh
./scripts/client-short-state-smoke.sh
```

成功時:

```text
AHOGE LEGEND short state smoke: PASS
```

Detach中のDEFENDはDODGEへ切り替わり、regrow後はPARRYへ戻ります。Projectileの見た目はGodot側で後続接続します。

## 工程1 2-client戦闘統合検証

工程1の戦闘機能を同一authoritative match内で連続実行し、個別smokeでは検出しにくい状態残留や順序依存を確認します。

```bash
./scripts/server-up.sh
./scripts/client-combat-integration-smoke.sh
```

成功時:

```text
AHOGE LEGEND combat integration smoke: PASS
```

LONG_TEST / SHORT_TESTを同じmatchへ参加させ、Hit、Defense cancel、Parry / Dodge / Just、Clash、Stagger、SHORT detach / Regrow、最終IDLE復帰までを通しで検証します。

## Authoritative Round Hit count

工程2の最初として、HitConfirmedが成立した攻撃側の現在ラウンドHit数をserver stateで加算し、両クライアントへ通知します。

```bash
./scripts/server-up.sh
./scripts/client-hit-count-smoke.sh
```

成功時:

```text
AHOGE LEGEND hit count smoke: PASS
```

PARRY / DODGE / Just / AttackClashではHit数を加算しません。5 Hit勝利やRound resetは後続Issueで接続します。

## Authoritative 85秒 Round timer

2人がauthoritative matchへ参加した後、Nakama 30Hz tickを正として85秒の整数カウントダウンを開始します。

```bash
./scripts/server-up.sh
./scripts/client-round-timer-smoke.sh
```

成功時:

```text
AHOGE LEGEND round timer smoke: PASS
```

serverは85から0までの値が変化したときだけ両クライアントへ通知します。0到達時のHit数比較・Overtime・Round終了は後続Issueで接続します。

## Authoritative 5 Hit Round win

現在ラウンドのHit数が5へ到達した時点で、server内部で勝者を確定し、両者をROUND_LOCKEDへ遷移させて戦闘とtimerを停止します。

```bash
./scripts/server-up.sh
./scripts/client-hit-limit-smoke.sh
```

成功時:

```text
AHOGE LEGEND hit limit smoke: PASS
```

Round Result通知・次ラウンドReset・timeout / Overtimeは後続Issueで接続します。

## Authoritative timeout Hit比較

85秒timerが0へ到達したserver tickで、それまでに確定済みのHit数を比較します。差がある場合は多い側をserver内部のラウンド勝者として確定し、両者をROUND_LOCKEDへ遷移させます。

```bash
./scripts/server-up.sh
./scripts/client-timeout-winner-smoke.sh
```

成功時:

```text
AHOGE LEGEND timeout winner smoke: PASS
```

同点の場合は勝者を確定せずOvertime待ちとして一旦ROUND_LOCKEDへ遷移します。Overtime開始・次Hit勝利は後続Issueで接続します。

## 設計・製造計画の正本

- `docs/PRODUCTION_PLAN.md`
- `docs/BASIC_DESIGN.md`
- `docs/DETAILED_DESIGN.md`
- `docs/SCREEN_DESIGN.md`
- `AGENTS.md`
