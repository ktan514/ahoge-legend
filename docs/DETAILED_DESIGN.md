# AHOGE LEGEND 詳細設計

## 1. 文書情報

- 対象プロダクト: `AHOGE LEGEND`
- 上位設計: `docs/BASIC_DESIGN.md`
- 画面設計: `docs/SCREEN_DESIGN.md`
- 文書目的: 基本設計を実装可能な論理構造、状態遷移、データ構造、判定責務へ分解する
- ステータス: 初版
- 作成日: 2026-09-26

この詳細設計は、採用技術を前提としつつ、ゲームルールとドメイン設計を特定SDKのAPIへ過度に結合しない形で定義する。

開発・公開環境は、Godot 4.7.2 stable、GDScript、Godot Editor + VS Code、Nakama、PostgreSQL、Docker Compose、AWS東京リージョン、Steamで進める。具体的なSDK API、Node構成、DBスキーマ、AWSリソース構成は、それぞれの実装Issueで詳細化する。

## 2. 設計原則

### 2.1 ルール判定と見た目を分離する

次を別系統として扱う。

1. 対戦ルール
2. キャラクター状態
3. 入力受付
4. 頭部モーション
5. アホ毛擬似物理
6. 描画・エフェクト
7. オンライン同期

アホ毛の見た目上の先端位置が偶然接触したかどうかだけで勝敗を決めない。

### 2.2 入力は頭部アクションを駆動する

入力でアホ毛を直接操作しない。

```text
Mouse Input
↓
Combat Action
↓
Head Motion
↓
Ahoge Secondary Motion
↓
Visual
```

対戦判定は `Combat Action` のルール定義に基づいて確定する。

### 2.3 アホ毛タイプと攻撃タイプを分離する

- アホ毛タイプ: 基本形状・基本モーション
- 攻撃タイプ: 戦闘時の使い方
- 攻撃範囲: 各攻撃定義が持つ判定情報

この3つを混同しない。

### 2.4 プロトタイプ値を本番定数にしない

HTMLプロトタイプで使用した以下のような値は操作感確認用であり、そのまま本番へ固定しない。

- チャージ秒数
- パリィ受付秒数
- ジャスト受付秒数
- 仰け反り秒数
- 擬似物理のばね係数
- モーション回転角
- 仮の5ヒット制

本番値は本番エンジン上のHuman Verificationで調整する。

## 3. 論理モジュール

### 3.1 GameFlow

責務:

- タイトル
- メニュー
- 対戦モード選択
- キャラクター選択
- マッチング
- 対戦前掛け合い
- バトル
- リザルト
- 再キュー／再戦／終了

GameFlowは個々の攻撃判定を持たない。

### 3.2 MatchCoordinator

責務:

- マッチ全体の状態
- ラウンド取得数
- 2本先取判定
- 次ラウンド開始
- マッチ終了
- 延長戦への遷移

### 3.3 RoundCoordinator

責務:

- 85秒タイマー
- 有効ヒット数
- 規定ヒット数到達判定
- 時間切れ判定
- 延長戦
- ラウンド勝者確定

### 3.4 CombatController

責務:

- プレイヤー入力から戦闘アクションへの変換
- 攻撃状態管理
- 防御状態管理
- 防御キャンセル
- 攻撃到達イベント生成
- パリィ／回避／相殺判定の要求

### 3.5 DefenseResolver

責務:

- 現在状態からパリィ可能か回避へ切り替えるかを判定
- 通常防御とジャスト防御を判定
- 防御結果を返す

### 3.6 ContactResolver

責務:

- 攻撃が有効ヒット位置へ到達した時刻を管理
- 両者の攻撃到達を比較
- 攻撃相殺を判定
- ヒット、パリィ、回避の最終結果を確定するためのイベントを生成

### 3.7 CharacterMotionController

責務:

- Idle
- Charge
- Windup
- Strike
- Cooldown
- Parry
- Dodge
- Stagger

などに対応する頭部モーションを生成する。

### 3.8 AhogeMotionController

責務:

- 頭部位置・速度・加速度を入力として受ける
- アホ毛タイプに対応する擬似物理を適用する
- 慣性
- 遅れ
- ばね
- 減衰
- 振り戻し
- 攻撃時の制御付き伸縮

を計算する。

### 3.9 OnlineSession

責務:

- Nakama client生成
- 開発用Device認証
- 認証済みSession保持
- 認証済みaccount取得
- ランダムマッチ
- ルームコードマッチ
- 対戦接続
- 対戦イベント同期
- サーバー確定結果の受信

Godotクライアントは公式 `heroiclabs/nakama-godot` v3.4.0 をvendorして使用する。
公式SDKは独自改変せず、公式`Nakama.gd`をAutoload名 `Nakama` として登録する。fresh checkoutではSDKの`class_name`一覧をGodotへ登録するため、通常実行・headless試験より先に`godot --headless --path . --import`を一度実行する。ゲーム固有の認証・接続責務は `OnlineSession` に集約する。

ローカル開発ではDevice Authenticationを使用する。
初回起動時にランダムなDevice IDを生成して `user://` 配下へ保存し、以降は同じIDを再利用する。
認証成功後は `NakamaSession` を `OnlineSession` が保持し、account取得まで成功した時点をローカル認証成立とする。

raw auth token、refresh token、password等は通常ログへ出力しない。
Device Authenticationは開発用であり、Steam公開時の正式認証方式は後続Issueで実装する。

Realtime SocketはDevice認証済みSessionを使用して接続する。
Matchmaker、Authoritative Match HandlerはRealtime Socket基盤の後続Issueで接続する。
Nakama側のカスタムサーバーロジックはTypeScriptを使用する。

### 3.10 RankingService

責務:

- ランクマッチ結果の登録
- プレイヤーRating更新
- プレイヤーランキング取得
- AHOGE LEGENDランキング用のキャラクター総勝利数更新
- AHOGE LEGENDランキング取得
- 月次シーズン切替
- 過去シーズン結果の保持

ランクマッチ終了時は、サーバーで確定した勝者に対してプレイヤーランキングを更新し、同時に勝者が使用していたキャラクターの当月総勝利数へ1を加算する。

フレンドマッチはプレイヤーランキング・AHOGE LEGENDランキングのどちらにも反映しない。

Rating方式は未決。

## 4. 画面状態遷移

### 4.1 ランクマッチ

```text
Title
→ MainMenu
→ OnlineMenu
→ RankedMatch
→ CharacterSelect
→ Matchmaking
→ MatchFound
→ PreBattleDialogue
→ RoundIntro
→ Battle
→ RoundResult
→ RoundIntro / MatchResult
→ RankedResultMenu
```

`RankedResultMenu`:

```text
NextMatch
CharacterChange
Exit
```

ランクマッチでは `Rematch` を持たない。

### 4.2 フレンドマッチ

```text
Title
→ MainMenu
→ OnlineMenu
→ FriendMatch
→ CreateRoom / JoinRoom
→ RoomCode
→ CharacterSelect
→ MatchReady
→ PreBattleDialogue
→ RoundIntro
→ Battle
→ RoundResult
→ RoundIntro / MatchResult
→ FriendResultMenu
```

`FriendResultMenu`:

```text
Rematch
CharacterChange
Exit
```

## 5. プレイヤー戦闘状態

### 5.1 状態一覧

| 状態 | 説明 |
| --- | --- |
| Idle | 通常待機 |
| Charging | 左クリック長押し中 |
| Windup | 攻撃発動前の予備動作 |
| Strike | 攻撃動作中 |
| Cooldown | 攻撃後の再使用待ち |
| Parry | アホ毛による迎撃 |
| Dodge | 頭部による回避 |
| Stagger | ジャスト防御・相殺等による行動不能 |
| RoundLocked | ラウンド開始前／終了後の操作禁止 |

### 5.2 基本遷移

```text
Idle
├─ LeftDown → Charging
├─ RightClick → Parry / Dodge
└─ RoundEnd → RoundLocked

Charging
├─ LeftUp → Windup
├─ RightClick → Parry / Dodge
└─ RoundEnd → RoundLocked

Windup
├─ WindupEnd → Strike
├─ RightClick → Parry / Dodge
└─ RoundEnd → RoundLocked

Strike
├─ StrikeEnd → Cooldown
├─ RightClick → Parry / Dodge
├─ JustDefenseReceived → Stagger
├─ AttackClash → Stagger
└─ RoundEnd → RoundLocked

Cooldown
├─ CooldownEnd → Idle
├─ RightClick → Parry / Dodge
└─ RoundEnd → RoundLocked

Parry / Dodge
├─ DefenseEnd → Idle または元のクールダウン状態
├─ JustSuccess → 相手をStagger
└─ RoundEnd → RoundLocked

Stagger
├─ StaggerEnd → IdleまたはCoolDown
└─ RoundEnd → RoundLocked
```

防御キャンセル時に攻撃を再開しない。

## 6. 入力処理

### 6.1 左クリック

#### Pointer Down

`Charging` へ遷移する。

#### Pointer Up

押下時間を確認する。

- チャージ閾値未満: 通常攻撃
- チャージ閾値以上: チャージ量を算出

その後 `Windup` へ遷移する。

### 6.2 右クリック

`DefenseResolver` へ現在状態を渡す。

概念:

```text
if ahoge_can_parry:
    defense = PARRY
else:
    defense = DODGE
```

攻撃状態中であれば、先に攻撃状態をキャンセルして防御状態へ遷移する。

### 6.3 長押し防御禁止

右クリックを押し続けても受付時間を延長しない。

1クリックにつき1回の防御アクションを生成する。

## 7. 攻撃処理

### 7.1 AttackDefinition

攻撃タイプは少なくとも次を持てる構造とする。

```text
AttackDefinition
- id
- motion_type
- windup_time
- strike_time
- cooldown_time
- charge_enabled
- charge_time
- attack_reach
- contact_timing
- contact_ratio
- projectile_enabled
- projectile_speed
- projectile_trajectory
- ahoge_detach
- ahoge_regrow_time
- defense_behavior_while_attacking
```

最終的なフィールド名は実装言語に合わせて調整する。

ローカル縦切りの初期実装では、論理接触時刻を `Strike開始 + strike_time * contact_ratio` として算出する。
`contact_ratio` は見た目のアホ毛先端位置とは独立した判定用パラメータとする。

### 7.2 通常攻撃

- 明確なWindupを持つ
- Strikeはチャージ攻撃より遅い
- Cooldownはチャージ攻撃より短い

### 7.3 チャージ攻撃

チャージ量 `0.0 .. 1.0` を持つ。

チャージ量から少なくとも次を補間可能とする。

- 攻撃到達速度
- Strike時間
- Cooldown
- モーション振り幅
- 必要に応じた攻撃性能

チャージ中は攻撃判定を出さない。

### 7.4 ショート投擲

`ahoge_detach = true` の攻撃では、投擲開始後に頭部側のアホ毛を不在状態にする。

投擲中:

- 飛翔アホ毛を別オブジェクトとして描画
- 頭部側は再生モーションを行う
- パリィ不能なら右クリックは回避へ切り替える

再生完了後:

- `ahoge_available = true`
- 右クリックは再びパリィへ戻る

オンラインauthoritative matchでは、選択済み `character_id` をMatchmakerからmatch stateへ引き渡し、初期縦切りでは `LONG_TEST / SHORT_TEST` を識別する。

`SHORT_TEST` のTHROW攻撃は、WINDUPからSTRIKEへ入ったserver tickをdetach開始tickとする。

- `ahoge_available = false`
- `regrow_until_tick = detach_tick + ceil(0.60 * 30)`
- 初期値は18tick
- detach時点の `COMBAT_STATE_CHANGED` を両クライアントへ通知する

Regrowタイマーは現在のaction stateから独立して進行する。DODGE、COOLDOWN、STAGGERへ遷移しても `regrow_until_tick` を保持し、`server_tick >= regrow_until_tick` で次を行う。

- `ahoge_available = true`
- `regrow_until_tick = -1`
- 現在action stateを維持したまま `COMBAT_STATE_CHANGED` を両クライアントへ通知する

`ahoge_available = false` 中の `DEFEND` は既存Defense規則どおりDODGEへ分岐し、通常DODGE / JUST_DODGE判定を使用する。Regrow後の `DEFEND` は再びPARRYへ分岐する。

`LONG_TEST` は攻撃時にdetachせず、`ahoge_available = true` を維持する。

Projectileの見た目・軌道・再生表現はGodotクライアント側の責務とし、server判定には使用しない。

## 8. 防御判定

### 8.1 DefenseContext

防御開始時に次を記録する。

```text
DefenseContext
- defense_type: PARRY / DODGE
- start_time
- active_until
- just_until
```

### 8.2 防御結果

```text
DefenseResult
- NONE
- PARRY
- JUST_PARRY
- DODGE
- JUST_DODGE
```

### 8.3 ジャスト判定

攻撃が有効ヒット位置へ到達した時点で、相手のDefenseContextを参照する。

オンラインauthoritative matchではクライアント時刻・描画フレーム・見た目のアホ毛位置を判定へ使用せず、ContactEventが到達したserver tickだけを基準にする。

Defenseのtick境界は次で固定する。

- Defense開始tickはactiveに含む
- `defense_active_until_tick` は終了境界とし、そのtick自体はactiveに含めない
- `defense_just_until_tick` は終了境界とし、そのtick自体はJustに含めない
- したがって `contact_tick < defense_just_until_tick` ならJust、Just終了後かつ `contact_tick < defense_active_until_tick` なら通常Defense、それ以外はNONE

Contact到達時に確定する結果は次とする。

```text
DefenseResult
- NONE
- PARRY
- JUST_PARRY
- DODGE
- JUST_DODGE
```

serverはContactEventを維持したまま、同じContactに対応するDefense結果を両クライアントへ通知する。

```text
DefenseResultEvent
- attacker_id
- defender_id
- input_sequence
- server_tick
- result
```

`input_sequence` は元の攻撃release sequenceと一致させ、ContactEventとDefenseResultEventを対応付ける。

DODGE / JUST_DODGEは `ahoge_available = false` のDefenseContextに対して同じtick規則を適用する。SHORT detach / regrowで `ahoge_available=false` を発生させ、DODGE / JUST_DODGEを実運用経路へ接続する。

### 8.4 ジャスト成功時

- 攻撃を無効化
- 防御側ノーダメージ
- 攻撃側をStaggerへ遷移
- 視覚・UI上で通常防御と区別する

オンラインauthoritative matchでは、`JUST_PARRY / JUST_DODGE` を確定したtickで攻撃側を `STAGGER` へ遷移させる。

## 9. 攻撃相殺

### 9.1 ContactEvent

攻撃が有効ヒット位置へ到達した時点で次を生成する。

```text
ContactEvent
- attacker_id
- defender_id
- attack_id
- reached_at
- contact_position
```

### 9.2 判定

オンラインauthoritative matchでは、両者の未解決Contact予定tickをserver側で比較する。

AttackClash許容差は実装開始用暫定値 `0.067秒` を使用し、30Hz server tickでは他の秒指定戦闘値と同じく `ceil(seconds * 30)` で量子化する。初期値は3tickとする。

判定順序は次で固定する。

1. 両者に未解決Contact予定tickが存在する場合、tick差を比較する
2. 差がAttackClash許容tick以内ならClash候補とする
3. Clash候補は早い側Contactだけで結果を確定せず、遅い側Contact予定tickへ到達するまで待つ
4. 遅い側Contact予定tick到達時点でも両攻撃が有効なら `AttackClash` を確定する
5. Clash候補でないContactは、そのContact tickでDefenseResultを確認する
6. DefenseResultが `NONE` なら `HIT`
7. DefenseResultが `PARRY / JUST_PARRY / DODGE / JUST_DODGE` のいずれかならHitを発生させない

Clash待機中にいずれかの攻撃がDefense cancel等で無効化された場合、残ったContactを通常のDefense / Hit判定へ戻す。

serverは次の確定イベントを両クライアントへ通知する。

```text
HitConfirmedEvent
- attacker_id
- defender_id
- input_sequence
- server_tick
```

```text
AttackClashEvent
- attacker_a_id
- attacker_b_id
- attacker_a_input_sequence
- attacker_b_input_sequence
- server_tick
```

ContactEventとDefenseResultEventは既存どおり維持する。HitConfirmedEventはDefenseResultがNONEのContactだけに追加し、AttackClashEventではHitConfirmedEventを生成しない。

### 9.3 相殺結果

- 両者ノーダメージ
- 両者Stagger
- ジャスト防御相当のエフェクト
- 通常ヒット処理を実行しない

オンラインauthoritative matchでは、AttackClashを確定したtickで両者を `STAGGER` へ遷移させる。

### 9.4 Stagger

StaggerはNakama authoritative matchのserver stateとして管理する。

初期値は実装開始用暫定値 `0.45秒` を使用し、30Hzでは他の秒指定戦闘値と同じく `ceil(seconds * 30)` で量子化する。初期値は14tickとする。

Stagger開始時は次を行う。

- stateを `STAGGER` へ変更する
- `stagger_until_tick = start_tick + stagger_ticks` を保持する
- 進行中の攻撃予定、未到達Contact、Defense active / Just、Defense後のCooldown復帰情報を破棄する
- `ahoge_available` は現在値を維持する
- `COMBAT_STATE_CHANGED` で両クライアントへ通知する

Stagger中は `ATTACK_PRESS / ATTACK_RELEASE / DEFEND` による戦闘状態遷移を行わない。

`server_tick >= stagger_until_tick` でStaggerを終了し、初期authoritative実装では現在のローカル戦闘 `CombatantState.apply_stagger()` と同じく `IDLE` へ復帰する。Stagger前のCooldownは再開しない。

Just DefenseとAttackClashの発生通知は既存イベントを維持し、Stagger状態は `COMBAT_STATE_CHANGED` を正とする。

## 10. ラウンド管理

### 10.1 RoundState

```text
RoundState
- round_number
- player1_hits
- player2_hits
- remaining_seconds
- overtime
- winner
```

オンラインauthoritative matchでは工程2を段階実装する。最初の段階ではラウンド終了条件をまだ接続せず、user IDごとの現在ラウンドHit数だけをserver stateで保持する。

```text
round_hit_count_by_user
- user_id -> hit_count
```

初期値は各参加者0とする。2人がauthoritative matchへjoinして対戦可能になった時点で、現在値0を両クライアントへ通知する。

Hit数の更新条件は次で固定する。

- `HitConfirmedEvent` を確定した攻撃側だけを+1する
- PARRY / JUST_PARRY / DODGE / JUST_DODGEでは加算しない
- AttackClashでは加算しない
- 同じ `input_sequence` のHitを二重加算しない。既存Contactの一度きり確定を前提とする
- Hit数更新直後に規定Hit数到達を判定する
- 初期規定値は5 Hitとする
- Round resetはRound lifecycle実装時に追加する

5 Hit到達時のserver state:

```text
round_finished = true
round_winner_user_id = 5 Hitへ到達した攻撃側user ID
round_finish_cause = HIT_LIMIT
```

5 Hit目の `RoundHitCountChangedEvent` を通知した後、同じserver tickで両者の戦闘状態を `ROUND_LOCKED` へ遷移させる。

`ROUND_LOCKED` 中は次を行わない。

- ATTACK_PRESS / ATTACK_RELEASE / DEFENDの適用
- 新規ContactEventの確定
- 新規HitConfirmedEvent
- Hit数加算
- Round timer更新

5 Hit到達時点のtimer表示値はRound Result lifecycleが接続されるまで最後のauthoritative値を保持し、クライアント側で勝手に0へ変更しない。

Round winnerのclient向け正式なRound Result通知、次ラウンドReset、取得ラウンド数への反映は後続工程で接続する。

server → client通知:

```text
RoundHitCountChangedEvent
- user_id
- hit_count
- server_tick
- input_sequence
```

初期値通知では `input_sequence = 0` とする。Hit加算通知では元の攻撃release sequenceを保持する。

Godotクライアントはこの通知を表示・同期用に受信するが、Hit数をクライアント側で独自加算して正本にしない。

### 10.2 タイマー

- 開始値: 85
- UI表示: 整数秒
- オンラインauthoritative matchではNakama server tickを正とする
- match tick rateは30Hzのため、85秒は2550tickとして管理する
- 2人がauthoritative matchへjoinし、最初のmatch loopへ入ったserver tickを `round_timer_start_tick` とする
- `round_timer_end_tick = round_timer_start_tick + 2550`
- 表示用 `remaining_seconds` は `ceil(max(0, round_timer_end_tick - server_tick) / 30)` で算出する
- 初回は85を通知し、その後は表示値が変化したときだけ84、83、…、0を通知する
- 0へ到達した後は0で停止し、負数へ進めない
- 5 Hitで `round_finished=true` になった場合もtimer更新を停止する
- クライアント側で独自カウントダウンを勝敗判定の正本にしない
- 0到達時のHit数比較・Overtime・Round終了は後続Issueで接続する

server → client通知:

```text
RoundTimerChangedEvent
- remaining_seconds
- server_tick
```

timer開始・更新・0到達はすべてserver tickから決定し、描画fps・Godot physics tick・ローカル時計は判定へ使用しない。

### 10.3 時間切れ処理

```text
if P1_hits > P2_hits:
    P1 wins round
elif P2_hits > P1_hits:
    P2 wins round
else:
    overtime = true
```

オンラインauthoritative matchでは、`remaining_seconds` が0へ変化したserver tickをtimeout境界とする。

判定順序を次で固定する。

1. match loop先頭でserver tickから `remaining_seconds` を更新する
2. 0へ変化した場合、その時点までにserverが確定済みの `round_hit_count_by_user` を比較する
3. Hit数に差があれば、多い側を `round_winner_user_id` として確定する
4. `round_finished = true`
5. `round_finish_cause = TIMEOUT`
6. 両者を `ROUND_LOCKED` へ遷移させる
7. 同じmatch loop内の新規combat入力・未確定Contactはtimeout後のHit数へ含めない

0到達tickでまだContactEventとして確定していない攻撃は無効とする。85秒という終了境界を跨いだHitをtimeout比較へ後付けしない。

同点の場合はこの段階で勝者を確定しない。

```text
round_finished = false
round_winner_user_id = ""
round_awaiting_overtime = true
```

Overtime開始処理が接続されるまでは両者を一旦 `ROUND_LOCKED` にして、timer 0のまま新規combatを停止する。次のOvertime実装で `round_awaiting_overtime` を解除し、サドンデス戦闘へ遷移させる。

timeout確定後またはOvertime待ち中は、client側でHit数・勝者・timerを独自更新しない。

### 10.4 Overtime

延長戦中は次の有効ヒットで即座にラウンド終了する。

オンラインauthoritative matchでは、timeout同点tickでは一旦 `round_awaiting_overtime = true` として両者を `ROUND_LOCKED` にする。timeout境界を跨いだ未確定入力・ContactをOvertimeへ持ち越さないため、このtickでは戦闘を再開しない。

次のserver tick先頭でOvertimeを開始する。

```text
round_awaiting_overtime = false
round_overtime = true
round_finished = false
round_winner_user_id = ""
round_finish_cause = NONE
```

Overtime開始時は両者のcombat stateを新しい `IDLE` へ初期化する。timeout前のCHARGING / WINDUP / STRIKE / COOLDOWN / Defense / Stagger / pending Contactは復元しない。SHORTのdetach / regrow状態も持ち越さず、Overtime開始時は `ahoge_available = true` から再開する。

server → client通知:

```text
RoundOvertimeStartedEvent
- server_tick
```

Overtime開始tickで `RoundOvertimeStartedEvent` を両clientへ通知し、その後に両者の `COMBAT_STATE_CHANGED(IDLE)` を通知する。timerは0のまま再開せず、Overtime中は `ROUND_TIMER_CHANGED` を追加送信しない。

Overtime中の勝敗規則:

- PARRY / DODGE / JUST_PARRY / JUST_DODGEでは終了しない
- AttackClashでは終了しない
- `HitConfirmedEvent` が成立した場合だけ攻撃側Hit数を+1する
- Hit count更新後、その攻撃側を `round_winner_user_id` として即座に確定する
- `round_finish_cause = OVERTIME_HIT`
- 両者を `ROUND_LOCKED` へ遷移する
- 5 Hit規定数よりOvertimeの「次Hit」規則を優先する

Overtime終了後は通常のラウンド終了と同様に新規combat / Contact / Hit / Hit count更新を停止する。

Round Result通知、取得ラウンド数への反映、次ラウンドResetは後続工程で接続する。

### 10.5 Round Result

server内部でラウンド勝者が確定した場合、終了原因に関係なく同一の `RoundResultEvent` を両クライアントへ1回だけ通知する。

対象終了経路:

- 5 Hit到達: `HIT_LIMIT`
- 85秒timeoutでHit数差あり: `TIMEOUT`
- Overtime中の次の有効Hit: `OVERTIME_HIT`

server → client通知:

```text
RoundResultEvent
- round_number
- winner_user_id
- loser_user_id
- finish_cause
- winner_hits
- loser_hits
- server_tick
```

初期 `round_number` は1とする。次ラウンド開始時のincrementはBO3実装で接続する。

`winner_hits / loser_hits` はResult確定tick時点のauthoritativeな現在ラウンドHit数を使用する。Overtimeでは勝利HitのHit count加算後にResultを確定する。

通知順序:

1. 最後のHitがある場合は `HitConfirmedEvent`
2. `RoundHitCountChangedEvent`
3. server内部でwinner / finish causeを確定
4. 両者を `ROUND_LOCKED` へ遷移
5. `RoundResultEvent` を1回だけ通知

timeout勝利ではtimer 0通知後、`ROUND_LOCKED`、`RoundResultEvent` の順とする。

クライアントは `RoundResultEvent` をラウンド結果の正本として扱い、Hit数やtimerから勝者を再計算しない。

この段階ではResult通知後も同じauthoritative matchを保持し、取得ラウンド数更新・次ラウンドReset・Round Intro・2本先取判定は行わない。それらは次工程「2本先取BO3」で接続する。

## 11. マッチ管理

### 11.1 MatchState

```text
MatchState
- round_wins_by_user
- current_round
- match_finished
- match_winner_user_id
- round_reset_pending
```

オンラインauthoritative matchは2本先取、最大3ラウンドで進行する。

```text
ROUNDS_TO_WIN_MATCH = 2
MAX_ROUNDS = 3
```

Round Result確定後、同じserver tickで次を行う。

1. `round_wins_by_user[round_winner_user_id]` を+1
2. `BO3ScoreChangedEvent` を両clientへ通知
3. 2勝へ到達した場合は `match_finished = true`
4. `match_winner_user_id` に2勝したuser IDを設定
5. 2勝未満なら `round_reset_pending = true`

server → client:

```text
BO3ScoreChangedEvent
- completed_round_number
- round_winner_user_id
- round_wins_by_user
- match_finished
- server_tick
```

Round Resultを通知したserver tickでは次ラウンドを開始しない。

`round_reset_pending = true` の場合、次server tick先頭で次ラウンドを開始する。

次ラウンド開始処理:

- `current_round += 1`
- `round_hit_count_by_user` を両者0へreset
- Hit count 0 snapshotを両clientへ通知
- `round_timer_start_tick = server_tick`
- `round_timer_end_tick = server_tick + 2550`
- `round_remaining_seconds = 85`
- timer 85を通知
- `round_finished = false`
- `round_winner_user_id = ""`
- `round_finish_cause = NONE`
- `round_awaiting_overtime = false`
- `round_overtime = false`
- 両者combat stateを新しいIDLEへreset
- SHORT detach / regrowを持ち越さず `ahoge_available = true`
- `round_reset_pending = false`

input sequenceはmatch単位の再送・順序検証値なので、Round間でresetしない。

server → client:

```text
RoundStartedEvent
- round_number
- round_wins_by_user
- server_tick
```

次Round開始時の通知順序:

1. `RoundStartedEvent`
2. 両者の `RoundHitCountChangedEvent(hit_count=0, input_sequence=0)`
3. `RoundTimerChangedEvent(remaining_seconds=85)`
4. 両者の `COMBAT_STATE_CHANGED(IDLE)`

いずれかが2勝した場合は次Roundを開始せず、両者を `ROUND_LOCKED` のまま維持する。
正式な `MatchResultEvent` は次工程で通知する。

BO3の最大ケースは次のとおり。

```text
Round 1: P1 win -> 1-0
Round 2: P2 win -> 1-1
Round 3: P1 win -> 2-1
match_finished = true
match_winner_user_id = P1
```

2勝確定後は新規combat / Contact / Hit / Hit count / timer更新を停止する。

### 11.2 Match Result

BO3でいずれかの取得ラウンド数が2へ到達した場合、serverはauthoritativeなMatch Resultを両クライアントへ1回だけ通知する。

server → client:

```text
MatchResultEvent
- winner_user_id
- loser_user_id
- round_wins_by_user
- final_round_number
- server_tick
```

通知条件:

- `match_finished = true`
- `match_winner_user_id` が空でない
- Match Result未通知

通知順序:

1. 最終Roundの `RoundResultEvent`
2. 最終Roundの `BO3ScoreChangedEvent(match_finished=true)`
3. `MatchResultEvent`

3イベントの `server_tick` は同じ最終Round終了tickとする。

`round_wins_by_user` は最終scoreをそのまま通知し、winner側は必ず2、loser側は0または1とする。`final_round_number` は最終Round番号で、2-0なら2、2-1なら3となる。

クライアントは `MatchResultEvent` をMatch勝敗の正本として扱い、Round Result列やscoreから独自にMatch勝者を再計算しない。

Match Result通知後もauthoritative matchは即座に破棄せず、両者は `ROUND_LOCKED` のままとする。新規Round / combat / Contact / Hit / Hit count / timer更新は行わない。

Rating / Ranking更新、UI-11表示、Matchmaker再検索、Friend Match再戦は後続工程で接続する。

### 11.3 対戦前掛け合い

```text
DialogueDefinition
- character_a
- character_b
- lines
- special_pair
```

専用掛け合いが存在しない場合は各キャラクターの汎用台詞から組み合わせる。

### 11.4 勝利台詞

```text
VictoryLineDefinition
- character_id
- opponent_id optional
- text
```

相手専用台詞がある場合は優先し、なければ汎用台詞を使用する。

## 12. キャラクターデータ

### 12.1 CharacterDefinition

```text
CharacterDefinition
- id
- display_name
- ahoge_type
- attack_type
- head_asset
- ahoge_asset
- motion_profile
- combat_parameters
- dialogue_set
- victory_line_set
```

### 12.2 AhogeType

```text
LONG
NORMAL
SHORT
```

これは攻撃範囲を意味しない。

### 12.3 MotionProfile

概念:

```text
MotionProfile
- idle
- charge
- windup
- strike
- cooldown
- parry
- dodge
- stagger
- pseudo_physics
```

各キャラクターはアホ毛タイプの共通MotionProfileを基準とし、固有補正を重ねられる。

## 13. モーション詳細

### 13.1 HeadMotion

HeadMotionはアクションごとに頭部のローカル位置・回転を生成する。

入力はアホ毛ではなくHeadMotionを選択する。

### 13.2 Ahoge Secondary Motion

入力:

- head_position
- head_velocity
- head_acceleration
- action_state
- charge_ratio
- character_motion_profile

出力:

- ahoge_rotation
- bend
- damping_response
- stretch_visual
- detached_state

完全な物理シミュレーション結果をゲーム判定には使用しない。

### 13.3 ロング型

主表現:

- 全体の前後スイング
- 後方への張り
- 前方への振り抜き
- Strike時の制御付き伸長
- 少しの遅れ・振り戻し

チャージ中は見た目サイズを拡大しない。

### 13.4 ショート型

主表現:

- 短い素早い二次動作
- 投擲タイプではDetach
- Projectileとして飛翔
- 頭部側でRegrow
- アホ毛不在時のDodge

### 13.5 中距離型

未設計。

ロングとショートの単純な中間値だけにせず、独自のモーション特性を設計する。

## 14. オンライン責務

### 14.0 ローカルオンライン基盤

オンライン実装の初期基盤は次で固定する。

| 項目 | 採用 |
| --- | --- |
| Nakama | 3.41.0 |
| Nakama Common / nakama-runtime | 1.48.0 |
| PostgreSQL | 16.8-alpine |
| Server Runtime | TypeScript |
| TypeScript compile target | ES5 |
| ローカル起動 | Docker Compose |

Nakama 3.41.0 と nakama-runtime 1.48.0 を対応組として固定し、どちらか一方だけを意図せず更新しない。

ローカル構成は `docker-compose.yml` を正とし、PostgreSQL → Nakama migration → Nakama server の順で起動する。

Nakamaのローカル公開ポート:

- 7349: gRPC
- 7350: HTTP / WebSocket API
- 7351: Nakama Console

TypeScript Runtimeは `server/nakama/src/` をソース、`server/nakama/build/index.js` を生成物とし、生成物はDocker build時に作成する。

ローカル疎通確認用として `ahoge_health` RPCを登録する。

```text
ahoge_health
→ service: ahoge-legend
→ status: ok
→ runtime: typescript
```

このRPCはゲームルールを持たず、サーバーRuntimeが正しく読み込まれていることだけを確認する。

Godot Nakama SDKとローカルDevice認証は次段階として接続する。
WebSocket、Matchmaker、Authoritative Match Handlerは認証基盤より後のIssueで接続する。

### 14.0.1 Godotクライアント接続・認証

初期クライアントSDK:

- Nakama Godot SDK 3.4.0
- SDK読込: 公式`Nakama.gd` Autoload（公式SDKは無改変）
- fresh checkout準備: `godot --headless --path . --import`
- 対象Godot: 4.x
- ローカルHTTP endpoint: `http://127.0.0.1:7350`
- ローカルserver key: `defaultkey`
- 開発用認証: Device Authentication

Device IDは次の要件を満たす。

1. 初回のみクライアントでランダム生成する
2. `user://ahoge_device_id.txt` へ保存する
3. 再起動後は保存済みIDを再利用する
4. 空文字・読み込み失敗時は新規生成する
5. auth tokenそのものはログへ出力しない

認証フロー:

```text
Godot
→ OnlineSession
→ NakamaClient
→ authenticate_device
→ NakamaSession
→ get_account
→ AUTHENTICATED
```

この段階ではHTTP APIのみを使用し、Realtime Socketは開かない。

### 14.0.2 Godot Realtime Socket

Device認証済みSessionからNakama Realtime Socketを生成する。

初期ローカル接続:

- endpoint: `ws://127.0.0.1:7350/ws`
- SDK: `Nakama.create_socket_from(client)`
- session: Device Authenticationで取得した `NakamaSession`
- `appear_online`: false
- connect timeout: 3秒

接続フロー:

```text
AUTHENTICATED
→ create_socket_from(client)
→ connect_async(session)
→ REALTIME_CONNECTED
```

`OnlineSession` はRealtime Socketのライフサイクルを保持し、少なくとも次を公開する。

- connect
- disconnect
- is_connected
- connected signal
- disconnected signal
- connection_failed signal

認証前のSocket接続は受け付けない。

この段階ではMatchmaker、match join、対戦入力送信、再接続制御を実装しない。
意図しない切断後15秒の復帰仕様は後続Issueで実装する。

Socket接続URLにはSession tokenが含まれるため、Nakama SDKのDEBUGログを通常運用で有効にしない。
HTTP認証と同様、raw tokenをログへ出力しない。

### 14.0.3 Ranked Matchmakerとauthoritative match骨格

ランクマッチの最小オンライン縦切りは次の順で成立させる。

```text
2 clients AUTHENTICATED
→ 2 clients REALTIME_CONNECTED
→ add_matchmaker_async
→ Nakama Matchmaker matched
→ server Matchmaker Matched hook
→ nk.matchCreate("ahoge_ranked", matched users)
→ matched event with match_id
→ both clients join_match_async(match_id)
→ same authoritative match
```

サーバーは `ahoge_ranked` Match Handlerを登録する。

初期Match Handler:
- tick rate: 30Hz
- expected user IDs: Matchmaker matched結果の2人
- join可能人数: 2人
- expected user以外のjoinを拒否
- join / leave presenceをstateへ保持
- この段階では戦闘入力・タイマー・勝敗を処理しない

クライアントはMatchmaker ticket、matched結果、joined match IDを保持する。
Matchmakerを開始するには認証済みRealtime Socketが必要とする。
match成立前のticketはcancel可能とする。

初期検索条件:
- min count = 2
- max count = 2
- string property: `mode=ranked`
- string property: `character_id`
- numeric property: `rating`
- 初期Rating範囲: 自分のRating ±100

`character_id` はCharacterSelectで確定した選択結果をMatchmakerへ渡すための契約とする。初期縦切りでserverが受理する値は `LONG_TEST / SHORT_TEST` とし、Matchmaker queryの検索条件には含めない。Matchmaker Matched hookはmatched userごとの `character_id` をauthoritative match init paramへ引き渡し、match stateでuser IDに対応付けて保持する。

CharacterSelect画面とオンラインGameFlowの本接続は後続工程で行うが、OnlineSessionのRanked Matchmaker開始APIは `rating` と `character_id` を受け取る形へ先に固定する。

この骨格上へ後続Issueで85秒タイマー、戦闘入力、ContactEvent、防御、相殺、BO3勝敗を順次移管する。

### 14.1 サーバー権威で確定する対象

採用構成では、少なくとも次をNakama側のサーバー権威で確定する。

- ラウンド状態
- 85秒タイマー
- ContactEvent
- 有効ヒット
- DefenseResult
- AttackClash
- Stagger付与
- ラウンド勝敗
- マッチ勝敗
- ランキング更新

### 14.2 クライアント側で行う対象

- ローカル入力
- 頭部モーション
- アホ毛擬似物理
- 補間
- エフェクト
- UI
- セリフ
- サーバー結果への視覚反映

### 14.3 同期方針

クライアントは入力または戦闘アクションを送信し、サーバー確定イベントを受信する方向を基本とする。

最初の戦闘入力プロトコルは次で固定する。

client → server:

- op code `1`: `COMBAT_INPUT`
- payload:
  - `input_sequence`: 正の整数。プレイヤー単位で単調増加
  - `action`: `ATTACK_PRESS / ATTACK_RELEASE / DEFEND`

server → clients:

- op code `101`: `INPUT_ACCEPTED`
- payload:
  - `user_id`
  - `input_sequence`
  - `action`
  - `server_tick`

authoritative matchは戦闘入力に対して次を検証する。

1. senderが現在join中のpresenceである
2. payloadがJSONとして解釈できる
3. `action` が許可された戦闘入力である
4. `input_sequence` が正の整数である
5. 同一userの直前受理sequenceより大きい
6. 同一userから同じserver tick内に既に入力を受理していない

検証に成功した入力だけを `INPUT_ACCEPTED` としてmatch参加者へbroadcastする。
重複・逆順sequence、不正payload、不正action、同一tickの2入力目は戦闘ロジックへ渡さず破棄する。

受理済みの `ATTACK_PRESS / ATTACK_RELEASE` はserver authoritativeな攻撃状態へ接続する。

初期server攻撃状態:

```text
IDLE
└─ ATTACK_PRESS → CHARGING

CHARGING
└─ ATTACK_RELEASE → WINDUP
                   → STRIKE
                   → CONTACT_REACHED
                   → COOLDOWN
                   → IDLE
```

`ATTACK_PRESS` を適用したserver tickをcharge開始tickとして保持する。
`ATTACK_RELEASE` 時は経過tickからcharge ratioを `0.0 .. 1.0` で算出し、既存CombatConfigと同じ線形補間でWindup / Strike / Cooldown時間を決定する。

authoritative matchは30Hzで進行するため、秒指定の戦闘時間は `ceil(seconds * 30)` でtickへ変換する。
Contact tickは `Strike開始tick + ceil(strike_seconds * contact_ratio * 30)` とする。

server戦闘値は `server/nakama/src/combat_config.ts` に集約し、Godot側 `src/config/combat_config.gd` の初期値と同じ値を使用する。
値の最終調整は引き続きHuman Verification対象であり、この移管によって確定値へ昇格させない。

server → client通知:

- op code `102`: `COMBAT_STATE_CHANGED`
  - `user_id`
  - `state`
  - `server_tick`
  - `charge_ratio`
- op code `103`: `CONTACT_REACHED`
  - `attacker_id`
  - `defender_id`
  - `server_tick`
  - `input_sequence`
  - `charge_ratio`

`DEFEND` はserver authoritativeなDefense stateへ適用する。

Defense適用時は `ahoge_available` を参照し、trueなら `PARRY`、falseなら `DODGE` へ遷移する。`ahoge_available=false` を発生させるSHORT detach / regrowは後続Issueで接続するが、Defense state自体は先に両分岐へ対応する。

DefenseContextはserver tickで次を保持する。

```text
DefenseContext
- state: PARRY / DODGE
- started_tick
- active_until_tick
- just_until_tick
- resume_state
- resume_remaining_ticks
```

初期値:

- PARRY active: 0.18秒 → `ceil(0.18 * 30)` tick
- DODGE active: 0.22秒 → `ceil(0.22 * 30)` tick
- Just window: 0.07秒 → `ceil(0.07 * 30)` tick

Defense開始時の遷移:

- `IDLE → PARRY / DODGE`
- `CHARGING → PARRY / DODGE` とし、charge中攻撃は破棄する
- `WINDUP → PARRY / DODGE` とし、予定済みStrike / Contactを破棄する
- `STRIKE → PARRY / DODGE` とし、未到達Contactを破棄する
- `COOLDOWN → PARRY / DODGE` の場合、残りCooldown tickを保存してDefense終了後に再開する
- `PARRY / DODGE` 中の新しいDEFENDは新しい1回のDefenseとしてactive / just windowを再設定する

Defense終了時は、保存済みCooldown残量がある場合だけ `COOLDOWN` へ戻し、それ以外は `IDLE` へ戻す。CooldownはDefense中に消費せず一時停止する。

Contact到達時点ではまだPARRY / DODGE成功結果やHitを確定しない。次段階でContactEventとDefenseContextを照合し、通常防御・Just・Hitをserver authoritativeで確定する。

通信遅延を考慮したContactEventの時刻補正と100ms上限の具体的な補正方式は後続Issueで実装する。


### 14.4 M1 Battle Core用authoritative実画面接続

工程2完了直後のM1 #53では、工程4のGameFlow完成を待たず、UI-10 Battleへ直接入るデバッグ導線を用意する。

M1用のデバッグ構成は次とする。

```text
Godot実ウィンドウ
├─ P1: OnlineSession
│   ├─ Device Authentication
│   ├─ Realtime Socket
│   └─ LONG_TEST / マウス操作
└─ P2: M1デバッグ用Nakama client/socket
    ├─ 実行ごとに別Device ID
    ├─ Realtime Socket
    └─ SHORT_TEST / Q・E操作

P1 + P2
→ 同一Ranked Matchmaker
→ 同一authoritative match
→ server確定event
→ UI-10 HUD / FighterVisual
```

M1では1つのGodot process内に2つのNakama clientを保持してよい。これは操作・描画を1画面で早期確認するためのデバッグ構成であり、本番Ranked GameFlowで1processに2playerを保持する仕様ではない。

操作:

- P1 左クリック押下: `ATTACK_PRESS`
- P1 左クリック解放: `ATTACK_RELEASE`
- P1 右クリック: `DEFEND`
- P2 Q押下: `ATTACK_PRESS`
- P2 Q解放: `ATTACK_RELEASE`
- P2 E: `DEFEND`

M1のBattle表示はローカル `MatchCoordinator / CombatResolver` から勝敗を再計算しない。次のauthoritative eventを表示の正本として使用する。

- `COMBAT_STATE_CHANGED`: Attack / Charge / Parry / Dodge / Stagger / ROUND_LOCKED
- `DEFENSE_RESOLVED`: PARRY / DODGE / JUST_PARRY / JUST_DODGE
- `ATTACK_CLASH`: CLASH
- `HIT_CONFIRMED`: Hit演出
- `ROUND_HIT_COUNT_CHANGED`: Hit数
- `ROUND_TIMER_CHANGED`: 85秒timer
- `ROUND_OVERTIME_STARTED`: OVERTIME
- `ROUND_STARTED`: Round番号
- `BO3_SCORE_CHANGED`: 取得Round数
- `MATCH_RESULT`: Match終了・最終score
- `ahoge_available`: SHORT detach / regrow表示

見た目の頭部・アホ毛二次動作は引き続きGodot client側で行い、serverの戦闘判定へ逆流させない。

M1デバッグ起動は通常GameFlowと分離し、起動引数 `--m1-battle` からUI-10へ直接入れる。M1用の内部2client構成、固定テストキャラクター、操作キーは検証専用であり、本番仕様へ昇格させない。

## 15. マッチメイキング

### 15.1 ランクマッチ

- キャラクター選択後にマッチングへ入る
- 2人固定で検索する
- Matchmaker propertyに `mode=ranked`、選択済み `character_id`、数値 `rating` を付与する
- 初期queryは `+properties.mode:ranked +properties.rating:>=MIN +properties.rating:<=MAX`
- 初期検索幅は自分のRating ±100
- Matchmaker Matched hookが authoritative match `ahoge_ranked` を生成する
- matched通知で受け取った `match_id` へ両クライアントがjoinする
- 試合後は再戦させない

検索幅拡大の正式初期値は、10秒ごとに±100ずつ広げ、最大±500とする。60秒経過後も検索を継続しUIへ待機延長を表示する。
初期Matchmaker接続Issueではまず±100の単一ticketまでを実装し、この段階的拡大は後続Issueで接続する。

### 15.2 フレンドマッチ

- ホストがルームを作成
- ルームコードを発行
- 参加者がルームコードを入力
- Ratingは変動させない
- 対戦後は再戦可能

フレンドルームコードは暫定で6文字とし、文字集合は `ABCDEFGHJKLMNPQRSTUVWXYZ23456789` を使用する。曖昧な `0/O/1/I` は除外する。ルーム終了時に無効化し、放置ルームは2時間で失効させる。

## 16. ランキング

### 16.1 月次シーズン

ランキングは月単位のシーズン制とする。

毎月1日0:00（日本時間/JST）に新しい `season_id` を開始し、当月ランキング値を新規に集計する。

前月のデータを物理削除してリセットするのではなく、シーズン単位で履歴を保持し、表示対象を新しい月へ切り替える。

概念データ:

```text
RankingSeason
- season_id
- starts_at
- ends_at
- state
```

月替わり境界時刻は毎月1日0:00（日本時間/JST、UTC+9）とする。内部時刻をUTCで保持する場合も、シーズン境界の判定はJSTへ換算して行う。

### 16.2 プレイヤーランキング

個人プレイヤー単位のランキングとする。

```text
PlayerSeasonRank
- season_id
- player_id
- rating
- rank_tier
- wins
- losses
```

- ランクマッチのみ対象
- フレンドマッチは対象外
- 月次シーズン切替時に新しい集計を開始
- 暫定Rating方式はElo
- 初期Ratingは1500
- K値は32
- 月次シーズン開始時はRating 1500から開始
- 暫定ランク帯は Bronze / Silver / Gold / Platinum / Diamond / Master
- クライアントからRatingを直接書き換えられない構造とする

### 16.3 AHOGE LEGENDランキング

キャラクター単位の月次ランキングとする。

順位決定値は、対象シーズン内の全プレイヤーによるランクマッチ総勝利数とする。

```text
AhogeSeasonRank
- season_id
- character_id
- total_match_wins
- total_ranked_matches
```

`total_match_wins` のみを順位決定値に使用する。

`total_ranked_matches` は運営上の使用率・バランス確認等に利用できるが、公開順位の決定には使用しない。

集計規則:

1. ランクマッチの勝敗をサーバーで確定する
2. 勝者プレイヤーの `PlayerSeasonRank` を更新する
3. 勝者がそのマッチで使用した `character_id` を取得する
4. 対応する `AhogeSeasonRank.total_match_wins` を1増加する
5. 両者の使用キャラクターの `total_ranked_matches` を必要に応じて更新する
6. フレンドマッチでは上記のランキング集計を行わない

ラウンド勝利数はAHOGE LEGENDランキングへ加算しない。BO3のマッチ全体に勝利したときだけ1勝を加算する。

個々のプレイヤーが同じアホ毛で何勝したかではなく、全プレイヤーの勝利数をキャラクターごとに合算する。

当月1位のキャラクターを、その月の「伝説のアホ毛」としてUI上で強調表示できる。

### 16.4 ランキング表示

ランキング画面は少なくとも次の2タブを持つ。

```text
Ranking
├─ PLAYER
└─ AHOGE LEGEND
```

AHOGE LEGEND側では、少なくとも次を表示する。

- 順位
- キャラクター／アホ毛
- 当月総勝利数
- 現在の対象月
- 1位への特別表示

過去シーズン表示を実装する場合は、現在月のランキングとは別の履歴表示として扱う。

## 17. 画面UI

画面一覧、画面遷移、ワイヤーフレーム、Godot Scene分割は `docs/SCREEN_DESIGN.md` を正本とする。

### 17.1 Battle HUD

少なくとも次を表示する。

- Player情報
- 相手情報
- 取得ラウンド
- 現在の有効ヒット数
- 85秒タイマー
- 延長表示
- 必要な攻撃／防御状態フィードバック

内部デバッグ情報は本番HUDへ表示しない。

### 17.2 Overtime

85秒終了時に同点であれば、通常タイマー表示を延長表示へ切り替える。

例:

```text
OVERTIME
NEXT HIT WINS
```

文言は最終UI設計で変更可能。

## 18. プロトタイプ専用機能の扱い

HTMLプロトタイプで使用した以下は本番仕様ではない。

- キー1/2/3によるキャラクター組み合わせ切替
- 仮CPUロジック
- 仮5ヒット制
- HTML Canvasでの描画
- プロトタイプPNG素材
- プロトタイプの内部デバッグ表示
- プロトタイプの個別バージョン番号

必要な知見だけ本番設計へ移植する。

## 19. アセット構成

### 19.1 キャラクター画像

最低限の論理単位:

```text
CharacterAssets/
  Head/
  Ahoge/
  Accessories/
  Effects/
```

本番では必要に応じてリグ・変形用に追加分割する。

アセットの頭部接点を基準点として保持し、アホ毛の稼働点を頭部との接点に一致させる。

公式提供素材を使用できる場合でも、ゲーム側の参照先を差し替え可能にし、特定素材のファイル構造へゲームロジックを直接依存させない。

### 19.2 音声アセット

音声は少なくとも次の用途へ分類できる構造とする。

```text
VoiceUsage
- ATTACK
- HIT
- PARRY
- DODGE
- WIN
- OTHER
```

配信から切り出した音声を候補として管理する場合は、ファイルだけを保存せず、出典情報を必ず対応付ける。

概念データ:

```text
VoiceAssetDefinition
- id
- character_id
- usage
- file_path
- transcript
- source_type
- source_url
- source_title
- source_timestamp
- rights_status
- rights_basis
- notes
```

`source_type` は少なくとも次を区別する。

```text
STREAM_CLIP
OFFICIAL_PROVIDED
ORIGINAL
THIRD_PARTY_LICENSED
```

`rights_status` は少なくとも次を区別する。

```text
PENDING
APPROVED
REJECTED
```

`PENDING` の素材は候補素材であり、公開ビルドへ組み込まない。

`APPROVED` へ変更する場合は、ガイドライン、holo Indie審査結果、公式提供条件、個別許諾など確認可能な根拠を `rights_basis` に記録する。

AIや実装者が、他作品で使用実績があることだけを理由に `APPROVED` へ変更してはならない。

### 19.3 ボイス依存の回避

対戦前掛け合いと勝利後セリフはテキストのみで成立する設計を維持する。

配信切り抜きボイスや公式提供ボイスが利用できない場合でもゲームが完成できるようにし、ボイス素材は必須依存にしない。

## 20. 検証方針

### 20.1 自動検証対象

技術選定後、少なくとも次を自動化候補とする。

- 状態遷移
- 85秒時間切れ
- 2本先取
- 延長戦
- ContactEvent
- 攻撃相殺
- 防御キャンセル
- パリィ／回避の状態分岐
- ジャスト判定
- ショート投擲中のパリィ禁止
- 音声アセットのrights_statusがPENDINGのまま公開対象へ含まれないこと
- プレイヤーランキングの月次シーズン切替
- AHOGE LEGENDランキングが全プレイヤーのランクマッチ総勝利数をキャラクター単位で集計すること
- フレンドマッチが両ランキングへ反映されないこと
- ラウンド勝利ではなくマッチ勝利だけがAHOGE LEGENDランキングへ加算されること
- Ranking更新権限

### 20.2 Human Verification必須対象

次は自動試験だけで完了扱いにしない。

- 攻撃が予見可能な速さか
- 通常攻撃とチャージ攻撃の差が明確か
- ロングアホ毛が頭部運動に連動して見えるか
- チャージ中の後方への張りが自然か
- パリィが「叩く／払い落とす」ように見えるか
- ショート投擲の視認性
- 回避モーションの分かりやすさ
- 5:4画面比率
- Windows実機操作感
- macOS対応時の実機操作感

### 20.3 工程1 2-client戦闘統合検証

工程1の完了判定では、個別smokeの成功だけでなく、同一authoritative match内で複数の戦闘状態を連続させても両クライアントの結果が一致することを確認する。

統合試験は新しい戦闘仕様を追加せず、既存のserver authoritative契約を連続シナリオで検証する。

初期統合シナリオ:

1. LONG_TESTの通常Hit
2. 攻撃中DEFENDによるAttack cancel
3. PARRYでHit抑止
4. JUST_PARRYで攻撃側STAGGER
5. Stagger終了後IDLE復帰
6. AttackClashで両者STAGGER
7. 両者IDLE復帰
8. SHORT_TESTのStrike開始detach
9. detach中DODGE
10. detach中JUST_DODGEで攻撃側STAGGER
11. SHORT Regrow
12. Regrow後PARRY復帰
13. 最後に両者がIDLEから新しい戦闘入力を受理できること

検証条件:

- 1つのmatch IDの中で上記を完走する
- server確定イベントはP1/P2で同一payloadを受信する
- 対象となる `COMBAT_STATE_CHANGED` はP1/P2で同一payloadを受信する
- 各シナリオは開始時点のevent indexまたは `input_sequence` を境界にし、過去eventを成功として再利用しない
- 次シナリオ開始前に必要なIDLE / Regrow完了を明示的に待つ
- raw auth tokenをログへ出力しない
- 既存の個別smokeもすべて回帰成功する

この統合試験で工程1の戦闘コア完了を判定し、Hit数・85秒timer・Round / Overtime / BO3は工程2へ分離する。

## 21. 実装開始用パラメータ

### 21.1 初期縦切りキャラクター

正式タレントを決定する前に、ゲームロジックとモーションを検証するため次の仮キャラクターを使用する。

```text
LONG_TEST
- ahoge_type: LONG
- attack_type: SWING

SHORT_TEST
- ahoge_type: SHORT
- attack_type: THROW
```

仮キャラクターは正式プレイアブルキャラクターとして扱わず、権利確認不要な仮素材で実装する。

### 21.2 戦闘初期値

| 項目 | 暫定値 |
| --- | ---: |
| ラウンド勝利必要ヒット | 5 |
| 通常攻撃Windup | 0.18秒 |
| 通常攻撃Strike | 0.20秒 |
| 通常攻撃Cooldown | 0.48秒 |
| 最大チャージ時間 | 0.60秒 |
| 最大チャージRelease Windup | 0.08秒 |
| 最大チャージStrike | 0.13秒 |
| 最大チャージCooldown | 0.82秒 |
| パリィ有効時間 | 0.18秒 |
| ジャストパリィ時間 | 0.07秒 |
| 回避有効時間 | 0.22秒 |
| ジャスト回避時間 | 0.07秒 |
| AttackClash許容差 | 0.067秒 |
| Stagger | 0.45秒 |
| ショート投擲Regrow | 0.60秒 |
| LONG_TEST contact_ratio | 0.70 |
| SHORT_TEST contact_ratio | 0.70 |

通常攻撃とチャージ攻撃の中間値は設定値から補間可能にする。

戦闘値はResource、設定オブジェクト等で一元管理し、状態クラスやSceneへマジックナンバーとして直接埋め込まない。

`contact_ratio = 0.70` は実攻撃判定の初期検証値であり、Human Verificationで調整可能とする。

### 21.3 クライアント更新

- 描画目標: 60fps
- Godot physics tick: 60Hzを初期値とする
- 見た目のアホ毛擬似物理はクライアント側で更新する
- 対戦結果判定はNakama authoritative stateを正とする

### 21.4 Nakama authoritative match

- server runtime: TypeScript
- match tick rate: 30Hz
- クライアントからサーバーへの戦闘入力は1 playerあたり1 tickに1受理までとする
- 各入力に単調増加する `input_sequence` を付与する
- serverはplayerごとのlast accepted sequenceとlast accepted tickを保持する
- duplicate / out-of-order sequenceは破棄する
- 同一tickの2入力目は破棄する
- 受理入力はserver tick付き `INPUT_ACCEPTED` として両clientへ通知する
- `ATTACK_PRESS / ATTACK_RELEASE` はserver authoritativeなIDLE / CHARGING / WINDUP / STRIKE / COOLDOWN状態へ適用する
- 秒指定戦闘値は30Hz基準で `ceil(seconds * 30)` によりtickへ量子化する
- charge ratioはserver tick差から算出する
- ContactEventはStrike開始とstrike時間・contact ratioからserver tickで確定する
- rollbackは初期実装では行わない
- `DEFEND` はserver authoritativeなPARRY / DODGE状態へ適用する
- Defense active / Just受付時間はserver tickで保持する
- 攻撃中DEFENDは予定済み攻撃・未到達Contactをキャンセルする
- COOLDOWN中DEFENDは残りCooldownを一時停止してDefense終了後に再開する
- Contact到達時のDefenseResultはserver tickで確定し、NONE / PARRY / JUST_PARRY / DODGE / JUST_DODGEを両clientへ通知する
- AttackClash許容差0.067秒は30Hzで3tickへ量子化する
- 両攻撃のContact予定tick差がClash許容tick以内なら遅い側Contact予定tickまで確定を待つ
- Clash候補が成立した場合はAttackClashを確定し、Hitを発生させない
- ClashでないContactはDefenseResultがNONEの場合だけHitを確定する
- Just Defense成功時は攻撃側をSTAGGERへ遷移させる
- AttackClash確定時は両者をSTAGGERへ遷移させる
- Stagger 0.45秒は30Hzで14tickへ量子化し、終了後はIDLEへ復帰する
- Matchmaker propertyの `character_id` をauthoritative matchへ引き渡し、初期縦切りではLONG_TEST / SHORT_TESTを識別する
- SHORT_TESTはStrike開始tickでahogeをdetachし、`ahoge_available=false` とする
- SHORT Regrow 0.60秒は30Hzで18tickへ量子化し、action stateと独立して進行する
- detach中DEFENDはDODGE / JUST_DODGE、regrow後DEFENDはPARRY / JUST_PARRYへ分岐する
- 現在ラウンドHit数はuser IDごとにserver stateで保持し、HitConfirmed確定時だけ攻撃側を+1する
- Hit数更新はRoundHitCountChangedEventとして両clientへ通知する
- 85秒timerはserver tickで85→0を管理する
- 5 Hit到達時は攻撃側をround winnerとして確定し、両者をROUND_LOCKEDへ遷移する
- timer 0到達時はそのtickのcombat処理より先に確定済みHit数を比較する
- timeout時にHit数差があれば多い側をwinner、同点ならround_awaiting_overtimeへ遷移する
- timeout同点時は次server tickでOvertimeへ入り、timer 0のまま両者をIDLEへ戻す
- Overtime中は次の有効Hitで即Round終了し、finish causeをOVERTIME_HITとする
- Round Result、Round reset、BO3勝敗は後続Issueで接続する
- 遅延補正の初期上限は100msとし、実通信試験で見直す

### 21.5 切断・再接続

- 意図しない切断後15秒間は再接続を許可する
- 同じNakama user IDで復帰した場合は同一プレイヤーとして復帰させる
- 15秒以内に復帰しなければ切断側のマッチ敗北とする
- サーバー障害や両者同時切断は別途エラー終了として扱い、Rating更新を行わない方向で実装する

### 21.6 プレイヤーランキング初期値

Eloの暫定式を使用する。

```text
initial_rating = 1500
K = 32
```

暫定ランク帯:

| ランク | Rating |
| --- | ---: |
| Bronze | 0 - 1199 |
| Silver | 1200 - 1399 |
| Gold | 1400 - 1599 |
| Platinum | 1600 - 1799 |
| Diamond | 1800 - 1999 |
| Master | 2000以上 |

月次シーズン開始時は全プレイヤーを1500から開始する。

この方式は初期実装用であり、プレイヤー分布を確認して後から変更できるようにする。

### 21.7 マッチメイキング初期値

- 初期検索幅: Rating ±100
- 10秒ごとに±100ずつ拡大
- 最大検索幅: ±500
- 60秒経過後も成立しない場合は検索を継続しつつUIへ待機延長を表示する

### 21.8 フレンドルーム

- コード長: 6文字
- 文字集合: `ABCDEFGHJKLMNPQRSTUVWXYZ23456789`
- `0/O/1/I` は除外
- ルーム終了で即時無効
- 未使用状態が2時間継続した場合は失効

## 22. 未決事項

実装者は以下を独断で確定しない。

- 中距離型モーション
- 正式な初期キャラクター
- 正式キャラクターごとの攻撃タイプ
- 暫定戦闘値の最終調整
- 遅延補正方式の最終調整
- 切断・再接続ルールの最終調整
- Rating方式・ランク帯の最終調整
- AWS内の具体的なリソース構成
- macOSリリース
- 画面比率の最終値

未決事項を変更する場合は、Issueで目的を明確にし、基本設計・詳細設計を先に更新してから実装する。
