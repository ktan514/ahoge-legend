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

攻撃到達が `just_until` 以内であればジャスト成功とする。

実際の受付時間は未決。

### 8.4 ジャスト成功時

- 攻撃を無効化
- 防御側ノーダメージ
- 攻撃側をStaggerへ遷移
- 視覚・UI上で通常防御と区別する

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

両者のContactEventの `reached_at` を比較する。

差分が相殺許容幅以内なら `AttackClash` とする。

相殺許容幅は未決。

### 9.3 相殺結果

- 両者ノーダメージ
- 両者Stagger
- ジャスト防御相当のエフェクト
- 通常ヒット処理を実行しない

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

### 10.2 タイマー

- 開始値: 85
- UI表示: 整数秒
- 内部ではフレーム時間またはサーバー時刻で管理し、表示時に整数へ変換する
- 0到達時に勝敗を判定する

### 10.3 時間切れ処理

```text
if P1_hits > P2_hits:
    P1 wins round
elif P2_hits > P1_hits:
    P2 wins round
else:
    overtime = true
```

### 10.4 Overtime

延長戦中は次の有効ヒットで即座にラウンド終了する。

## 11. マッチ管理

### 11.1 MatchState

```text
MatchState
- player1_rounds
- player2_rounds
- current_round
- match_winner
```

いずれかの取得ラウンドが2になった時点でマッチ終了。

### 11.2 対戦前掛け合い

```text
DialogueDefinition
- character_a
- character_b
- lines
- special_pair
```

専用掛け合いが存在しない場合は各キャラクターの汎用台詞から組み合わせる。

### 11.3 勝利台詞

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

通信遅延を考慮したContactEventの時刻処理、補正方式、tick rateは未決。

## 15. マッチメイキング

### 15.1 ランクマッチ

- キャラクター選択後にマッチングへ入る
- Ranking/Ratingに近い相手を優先する方向
- 待ち時間に応じた検索範囲拡大は候補
- 試合後は再戦させない

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
- クライアントからサーバーへの戦闘入力は原則1 tickあたり1メッセージ以下
- 各入力に単調増加する `input_sequence` を付与する
- rollbackは初期実装では行わない
- サーバーは受信順だけでなく、match tickと入力sequenceを使用して重複・順序異常を検出する
- ジャスト判定、相殺、勝敗はサーバー権威で確定する
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
