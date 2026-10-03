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

`LONG / NORMAL / SHORT` はキャラクターそのものではなく、アホ毛の戦闘特性を分類するタイプである。正式ロスターでは各タイプに複数キャラクターを実装し、タイプごとの人数はおおむね均等になるよう構成する。

ランキング・戦績・選択状態の識別単位はタイプではなく個別の `character_id` とする。AHOGE LEGENDにLONG別・NORMAL別・SHORT別のタイプランキングは設けない。

現在の `LONG_TEST / SHORT_TEST` はオンライン戦闘基盤を検証するためのテストキャラクターIDであり、製品の正式ロスター数やタイプ数を示すものではない。

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

#### 3.9.1 ユーザー永続データの正本

ユーザーに紐づく永続的なゲーム状態はclientローカルファイルを正本にしない。

- ユーザー識別の正本はNakama `user_id`
- gameplay / account / progression / ranking / match状態などのユーザー永続データはNakama Storage Engineを正本とする
- Nakama Storage EngineはPostgreSQLへ永続化される
- 独自ユーザーマスタを二重管理しない
- custom SQL / custom tableは、Nakama標準Storageで表現できない明確な要件がない限り使用しない
- clientはserver状態の一時runtime cacheを持てるが、再起動後の正本にはしない
- `user://active_online_match.json` のようなgameplay状態ファイルは禁止する
- 端末固有Device IDは開発用Device Authenticationを成立させるためのcredentialであり、gameplay/account状態の正本には使用しない
- Steam Authentication導入後の本番ユーザー識別はSteam/Nakamaへ移行する

端末固有の表示・音量・入力設定など、account正本ではなく端末設定として扱う情報を将来ローカル保存する場合は、ユーザーgameplayデータと明確に分離する。

#### 3.9.1.1 UI-02端末ローカル設定

UI-02 Settingsの値はaccount / gameplay状態ではなく端末設定として扱い、`user://settings.cfg` を正本とする。Nakama Storageへは保存しない。

保存キー:

```text
[audio]
master_volume = 0..100
bgm_volume    = 0..100
se_volume     = 0..100
voice_volume  = 0..100

[display]
mode       = "windowed" | "fullscreen"
resolution = "1280x720" | "1600x900" | "1920x1080"
vsync      = true | false
```

初期値:

```text
Master = 100
BGM    = 100
SE     = 100
Voice  = 100
Mode   = windowed
Resolution = 1280x720
VSync  = true
```

契約:

- 起動時にSettingsStoreがConfigFileを読み込み、不正値・未知値は初期値へ正規化する
- 保存ファイルがない場合は初期値を使用する
- APPLYだけがruntime反映と保存を行う
- DEFAULTは編集値を初期値へ戻すだけで、APPLYするまでruntime状態を変更しない
- BACKは未APPLY編集値を破棄する
- AUDIOはGodot Audio Bus `Master / BGM / SE / Voice` へ反映する
- volume 0はmute、1〜100はlinear値をdBへ変換する
- DISPLAYは `DisplayServer` へ反映する
- Resolution UIはWindow時だけ有効、Fullscreen時は非活性とする
- Fullscreen中も選択Resolutionは保存し、Windowへ戻した時にそのsizeを適用する
- キーコンフィグは初期対象外。CONTROLは固定説明表示のみ
- SettingsStoreはUIから分離し、後続の入力設定追加でも画面ロジックへ永続化処理を埋め込まない

#### 3.9.2 Active Online Match

未解決online matchはユーザーごとのserver-side Storage objectで管理する。

```text
collection = active_online_match
key        = current
user_id    = Nakama user_id
```

1ユーザーにつき未解決online matchは最大1件とする。

保持内容:

```text
match_id
match_mode        # ranked / friend
state             # ACTIVE / RESULT_PENDING
created_at_unix_ms
updated_at_unix_ms
result_snapshot   # RESULT_PENDING時のserver確定結果
```

Storage objectはserver-only read/writeとし、clientは専用RPC経由でのみ照会・acknowledgeする。

状態遷移:

```text
match成立
→ ACTIVE

server authoritative match終了
→ RESULT_PENDING
  + server確定Result snapshotを永続化

clientが遷移先を確定
→ acknowledge
→ active_online_match/current を削除
```

起動時およびONLINE BATTLE開始前は、認証後の現在`user_id`についてserverへactive matchを問い合わせる。

- active contextなし → 通常導線
- ACTIVEかつserver上にmatchあり → 同じauthoritative matchへ復帰
- ACTIVEだがserver上にmatchなし → server側でstale contextを安全解除し通常導線
- RESULT_PENDING → DBに保存されたserver確定Resultから結果導線へ復帰
- 他userのactive context → 現在userへ影響させない

未解決matchの有無を「ローカルファイルが存在するか」で判定してはならない。

### 3.10 RankingService

責務:

- ランクマッチ結果の登録
- プレイヤーRating更新
- PLAYER Ranking取得
- キャラクター単位のAhoge Rating更新
- 単一のAHOGE LEGEND Ranking取得
- 参考統計としての勝数・対戦数・勝率保持
- 月次シーズン切替
- 過去シーズン結果の保持

#### 3.10.1 ランキングの単位

AHOGE LEGEND Rankingは **個別キャラクター（個別アホ毛）単位の1ランキングのみ** とする。

- 集計キーは `character_id`
- `LONG / NORMAL / SHORT` はランキング単位にしない
- タイプ別ランキング、タイプ別レート、タイプ別タブは作らない
- 正式ロスターでは各タイプに複数キャラクターが存在する
- 同一タイプでも別 `character_id` なら別アホ毛としてRatingを持つ

#### 3.10.2 AHOGE LEGENDの順位値

従来の「当月総勝利数」を順位値として使う方式は廃止し、キャラクターごとの **Ahoge Rating** をAHOGE LEGENDの唯一の順位値とする。

各シーズンのAhoge Rating初期値は共通基準 `1500` とする。

順位はAhoge Rating降順で決定する。同Ratingは同順位とする。総勝利数・対戦数・勝率・使用率は参考統計として保持できるが、順位決定やtie-breakには使用しない。

このRatingが表すものは「そのキャラクターを使用したプレイヤーの実力差を考慮したうえで、そのアホ毛自体が対戦結果へどれだけ寄与したと評価できるか」である。

#### 3.10.3 プレイヤー実力を補正した期待勝率

Ahoge Rating更新では、試合開始前のPlayer RatingとAhoge Ratingの両方を使用して期待勝率を求める。

概念式:

```text
effective_A = player_rating_A
            + ahoge_weight * (ahoge_rating_A - AHOGE_BASE_RATING)

effective_B = player_rating_B
            + ahoge_weight * (ahoge_rating_B - AHOGE_BASE_RATING)

expected_A
= 1 / (1 + 10 ^ ((effective_B - effective_A) / 400))

actual_A = 1  # A勝利
actual_A = 0  # A敗北

delta
= ahoge_k * (actual_A - expected_A)

ahoge_rating_A_after = ahoge_rating_A_before + delta
ahoge_rating_B_after = ahoge_rating_B_before - delta
```

`AHOGE_BASE_RATING = 1500` とする。

`ahoge_weight` と `ahoge_k` の最終値は固定せず、対戦シミュレーションと実データを使って調整する。Rating全体のインフレ／デフレを避けるため、異なるアホ毛同士の1試合では原則として同じ絶対量を一方へ加算し、他方から減算する。

実装では `server/nakama/src/ahoge_rating_config.ts` を調整値の単一正本とする。`AHOGE_BASE_RATING=1500` は仕様値、`ahoge_weight / ahoge_k / K安定化stage` はbalance調整値として分離する。初期実装は動作検証用defaultを持てるが、本番balance確定値とは扱わない。計算関数やUIへ調整値を重複記述しない。

`ahoge_k` はデータ量が少ない時期ほどRatingが動きやすく、十分な対戦数が蓄積した後は安定するよう、両キャラクターのシーズン対戦数を考慮して段階的または連続的に縮小できる構造とする。初期実装では安定化stageを空にでき、balance検証でstageを追加するだけで計算ロジックを変更せず調整できるようにする。具体的な閾値・係数はbalance検証で確定する。

#### 3.10.4 更新量の意図

同じ勝敗でも、事前期待によってAhoge Rating変動量を変える。

- 高Ahoge Ratingが低Ahoge Ratingへ順当に勝つ → 変動は小さい
- 低Ahoge Ratingが高Ahoge Ratingへ勝つ → 変動は大きい
- 高Player Ratingが高Ahoge Ratingを使って順当に勝つ → 変動はさらに小さい
- 低Player Ratingが不利なAhoge Ratingで格上側へ勝つ → 大きく上昇する
- Player Rating差が大きい場合、そのプレイヤー実力差をAhoge Ratingへそのまま転嫁しない

Player Ratingは「その人が強かったから勝った部分」を補正するための入力であり、AHOGE LEGEND Rankingそのものの順位値にはしない。

Player Ratingの更新は既存PLAYER Ranking用Eloとして独立して行い、Ahoge Ratingの計算には **試合開始前のPlayer Rating** を使用する。

Draw時のPlayer RatingとAhoge Ratingは別々に計算する。

- Player Rating: `actual = 0.5`。同一character対戦でも通常計算する
- Ahoge Rating: 異character対戦では `actual = 0.5`、同一character対戦では常にdelta 0
- Rating差があるDrawでは、期待値0.5を上回る側（格下側）が上昇し、下回る側（格上側）が低下する
- Friend Matchは両Ratingとも非対象

authoritative match生成時に、Rankedだけ次をmatch stateへ固定する。

```text
rating_season_id
player_rating_before_by_user
ahoge_rating_before_by_character
ahoge_match_count_before_by_character
```

期待勝率とK係数は、Match終了時の最新値ではなくこの**試合開始時snapshot**だけを入力とする。これにより同じcharacterが別matchで同時使用され、その別matchが先にsettlementしても、当該matchの期待勝率は開始時点の条件から変化しない。

一方、Ahoge RatingのStorage更新では他matchの更新を上書きしない。今回matchのdeltaを試合開始時snapshotから計算したうえで、settlement時に読み直した現在のStorage Ratingへそのdeltaだけを加減し、Storage versionによる楽観的排他で競合時は再読込・再試行する。

match単位settlementは、期待値計算用の開始時snapshotと、Match開始時刻が属するSeasonでのbefore / after / deltaを保持する。AHOGE LEGEND Rankingの現在値は、並行して完了した他matchの寄与も含むStorage正本を投影する。

#### 3.10.5 同一アホ毛対戦

同じ `character_id` 同士の対戦では、どちらが勝っても「そのアホ毛が別のアホ毛より強い」という情報を得られない。

そのため同一アホ毛対戦では:

- Ahoge Ratingを変動させない（勝敗・Drawとも±0）
- Player Ratingは通常どおり更新する（Draw時も実績値0.5で変動し得る）
- 勝敗・対戦数等の参考統計は記録できる
- タイプが同じでも `character_id` が異なる場合は通常のAhoge Rating更新対象とする

#### 3.10.6 server authoritative

Ahoge Rating更新はNakama serverだけが行う。

serverは少なくとも次を確定情報として使用する。

```text
season_id
match_id
winner_user_id
loser_user_id
winner_character_id
loser_character_id
player_rating_before_by_user
ahoge_rating_before_by_character
ahoge_rating_after_by_character
rating_delta_by_character
total_match_wins
total_ranked_matches
```

clientは期待勝率・Ahoge Rating・変動量を再計算しない。UIはserver settlement後の値を取得して表示する。

`ahoge_season_rank` storageをキャラクター別シーズン集計の正本とし、少なくとも `season_id / character_id / ahoge_rating / total_match_wins / total_ranked_matches` を保持する。旧recordに `ahoge_rating` がない場合は1500として読み取り、次回settlement時に新形式へ保存する。

Nakama leaderboardはAhoge Rating順の投影として扱う。leaderboard scoreはAhoge Ratingとし、勝数・対戦数はmetadataまたはstorage正本から返す。旧勝数scoreが残っているseasonでもRanking RPC取得時に既存storage recordを新Rating scoreへ再投影し、勝数とRatingが混在した順位を返さない。

`ranked_match_settlement` はmatch単位のserver確定settlement正本とし、Player RatingとAhoge Ratingのbefore / after / delta、期待勝率、使用character、mirror判定を保存する。同一matchのretryでは再計算せず、このsettlement recordを使用してleaderboard投影だけを再試行する。

clientはmatch IDを指定して専用RPCから自分自身のsettlement結果を取得できる。RPCはそのmatchのwinner / loser以外へsettlement値を返さない。UI-11はこのRPCだけをPlayer Rating / Ahoge Rating変動の正本とし、通常Match Resultでも `RESULT_PENDING` からの再ログイン復帰でも同じ表示契約を使用する。

フレンドマッチはPlayer Rating・Ahoge Rating・PLAYER Ranking・AHOGE LEGEND Rankingのいずれにも影響しない。

#### 3.10.7 Rating耐不正設計

Rating総量のインフレと、少人数によるAHOGE LEGEND操作を防ぐため、server settlementへ耐不正制約を入れる。

Player Rating:

- Elo期待値計算は従来どおり行う
- 片側deltaを整数化した後、相手deltaは必ずその符号反転値とする
- 1matchのPlayer Rating変動は常に `delta_A + delta_B = 0`
- 同一character対戦でも通常どおりPlayer Ratingを更新する
- Drawも `actual=0.5` として同じゼロサム制約を適用する

Ahoge Rating:

- 異character対戦の生deltaは従来の期待勝率式から算出し、相手deltaは必ず符号反転値とする
- 同一character対戦は勝敗・Drawともdelta 0
- `1 player × 1 character × 1 season` ごとに、そのplayerがそのcharacterへ与えた **絶対deltaの累積値** をserver Storageへ保持する
- 累積絶対影響量が上限へ達したplayer-characterは、そのSeason中それ以上Ahoge Ratingを動かさない
- 両participantの残り影響枠の小さい方を採用し、Ahoge Ratingのゼロサム性を維持する
- 同一player pairのSeason内対戦回数をserver Storageへ保持し、反復対戦ほどAhoge Rating影響を減衰する
- 両playerのaccepted combat input合計が0のMatchは完全無操作とみなし、Ahoge Rating deltaを0にする
- 勝数・対戦数等の参考統計はRating信頼度0でも実Match結果として更新してよい

耐不正Storage:

```text
collection: ahoge_player_character_influence
user_id: <player_id>
key: <season_id>:<character_id>
value:
- season_id
- character_id
- absolute_influence_used

collection: ahoge_opponent_pair
user_id: system
key: <season_id>:<small_user_id>:<large_user_id>
value:
- season_id
- first_user_id
- second_user_id
- ranked_match_count
```

初期実装の調整用default:

```text
player_character_absolute_cap = 100
same_pair_full_weight_matches = 5
same_pair_reduced_weight_matches = 10
same_pair_reduced_weight = 0.5
same_pair_min_weight = 0.25
no_activity_weight = 0.0
```

これらは本番balance確定値ではない。`ahoge_rating_config.ts` を単一正本とし、シミュレーション・実運用データ・abuse検証で調整する。

Ahoge Rating適用順:

```text
raw_delta
→ same-pair trust multiplier
→ no-activity判定
→ 両player-characterの残りabsolute influence枠でclamp
→ effective_delta
→ character Aへ +effective_delta
→ character Bへ -effective_delta
```

`ranked_match_settlement` には raw / trust / cap適用後delta、pair対戦回数、activity countを保存し、後から不正パターンを監査できるようにする。


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

#### 4.1.1 工程4前半のGodot GameFlow契約

工程4前半では既存ローカル縦切りを残したまま、`AppRoot` に `local / ranked` の画面文脈を持たせる。

```text
UI-01 TopMenu
  ONLINE BATTLE
    → UI-03 BattleModeSelect
      RANKED MATCH
        → Device Authentication / Realtime Socket確保
        → UI-04 CharacterSelect(mode=ranked)
        → UI-05 RankedMatching
        → authoritative match join
        → UI-09 PreBattleDialogue
        → UI-10 OnlineBattle
        → UI-11 MatchResult(mode=ranked)
```

`AppRoot` は画面遷移とonline flow contextだけを保持し、戦闘結果を再計算しない。

Ranked flow contextは少なくとも次を持つ。

```text
mode = ranked
selected_character_id
rating_before
match_id
initial_match_snapshot
authoritative_match_result
```

UI-04のRanked文脈では自分のcharacterだけを選択する。ローカル縦切り文脈では既存のP1/P2同時選択を維持する。

UI-05は `OnlineSession.start_ranked_matchmaking()` を使用し、検索幅・経過時間・cancelを表示する。match成立前に相手情報を表示しない。

authoritative matchへ通常joinした場合もserverはjoinしたplayerへ `MATCH_SNAPSHOT` を送信する。これによりUI-09/UI-10はclient推測ではなく、server snapshotの `character_id_by_user` / `round_wins_by_user` / `match_mode` を初期状態の正本として使用する。

UI-09初期実装は正式台詞コンテンツを要求せず、snapshotで確定した双方のcharacterと `READY...` を短時間表示する機能優先版とする。スキップ可否は未決のまま追加しない。

UI-10 Rankedは既存M1 HUD表現を再利用するが、M1デバッグ用の第二client自動生成は使用しない。実際の相手はremote playerとし、ローカルplayerの入力だけを `OnlineSession.send_combat_input()` でserverへ送る。

UI-11 Rankedは `MATCH_RESULT` のwinner / final score / finish_causeを勝敗正本として表示する。RatingはMatch Resultからclient計算しない。`match_id` を使ってserverのRanked settlement RPCを取得し、Player Ratingと使用characterのAhoge Ratingをそれぞれ `before → after (delta)` で表示する。再ログインResultでも同じsettlement RPCを使用するため、clientローカルにmatch前Ratingを保存して正本化しない。

UI-11 Rankedの操作は次のみとする。

```text
NEXT MATCH       → UI-04 CharacterSelect
CHANGE CHARACTER → UI-04 CharacterSelect
EXIT             → UI-01 TopMenu
```

Rankedでは `REMATCH` を表示しない。

通常Match ResultをUI-11へ接続した時点で、そのmatchの保存済み未解決contextは遷移先確定済みとして解除する。再ログイン復帰の場合も、`ranked_result` のUI-11表示を確定してから解除する。

起動時に認証後の現在userへserver-side active matchがある場合は新規Rankedを開始せず、active match復帰を優先する。clientローカルファイルの存在は判定に使用しない。

さらに、未解決Ranked match contextが残っている状態でUI-03の `RANKED MATCH` を選択した場合、警告表示だけで操作を止めてはならない。AppRootは新規matchmakingへ進まず、`RESTORING ORIGINAL MATCH...` を表示して既存matchのserver確認と復帰を強制開始する。UI-04からUI-05へ進む直前に未解決contextを検出した場合も同じ強制復帰を行う。

強制復帰はserver-side `active_online_match/current` を正本とし、server RPCが返したactive contextとauthoritative snapshot / Resultだけで復帰先を決定する。

復帰時の接続契約は次で固定する。

- 1回のserver接続timeoutは10秒
- 初回失敗後のretry上限は2回（初回を含め最大3 attempts）
- retry対象は認証・Realtime接続・server snapshot確認など、server確認が成立しなかった場合
- retry上限まで失敗した場合は未解決match lockを保持したままUI-01 TopMenuへ戻す
- TopMenuへ戻った後、ユーザーが再度 `ONLINE BATTLE` を選択した時点で同じ復帰処理を初回から再実行する
- 復帰不能中は新規matchmakingを開始しない

復帰結果は次のとおり扱う。

- 進行中Ranked → 同じauthoritative matchのserver snapshotを取得してUI-10へ強制復帰
- 終了済みRanked → serverから確定済みMatch Resultを含むsnapshotを取得してUI-11へ表示し、その後は通常の `NEXT MATCH / CHANGE CHARACTER / EXIT` へ進む
- server未確認 / network error → 上記10秒timeout・最大2 retryを適用し、上限到達後はlock維持のままTopMenuへ戻す
- Match Not Found / Invalid Match ID → 既存安全解除契約に従う
- clientは元matchの勝敗・状態・復帰先を推測しない

通常Ranked joinでは、前matchの `latest_match_snapshot` をjoin開始前に破棄する。serverからjoin直後に届いた新しい `MATCH_SNAPSHOT` を `join_match_async()` 完了後に再度消去してはならない。UI-09 / UI-10はこの最初のserver snapshotを初期状態の正本として使用する。

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
3. Hit数に差があれば、多い側へラウンドポイントを1点加算する
4. Hit数が同点なら、両者へラウンドポイントを1点ずつ加算する
5. 両者を `ROUND_LOCKED` へ遷移させる
6. 同じmatch loop内の新規combat入力・未確定Contactはtimeout後のHit数へ含めない
7. ラウンドポイント反映後に2点到達を判定する
   - 片側だけ2点 → そのplayerのMatch Win
   - 両側同時2点 → Match Draw
   - どちらも2点未満 → 次Round

0到達tickでまだContactEventとして確定していない攻撃は無効とする。85秒という終了境界を跨いだHitをtimeout比較へ後付けしない。

同点時もOvertimeへ遷移しない。旧 `round_awaiting_overtime / round_overtime / OVERTIME_HIT` は製品勝敗経路では使用しない。

同点Roundのserver状態:

```text
round_finished = true
round_winner_user_id = ""
round_finish_cause = TIMEOUT_DRAW
round_draw = true
```

Match Draw:

```text
match_finished = true
match_winner_user_id = ""
match_finish_cause = BO3_DRAW
match_draw = true
```

### 10.4 同点ラウンド

同点ラウンドは `TIMEOUT_DRAW` として両者へ1点を加算する。次の例を正式挙動とする。

```text
0-0 → Draw Round → 1-1 → 次Round
1-0 → Draw Round → 2-1 → P1 Match Win
0-1 → Draw Round → 1-2 → P2 Match Win
1-1 → Draw Round → 2-2 → Match Draw
```

Overtime / サドンデスは行わない。
### 10.5 Round Result

server内部でラウンド勝者が確定した場合、終了原因に関係なく同一の `RoundResultEvent` を両クライアントへ1回だけ通知する。

対象終了経路:

- 5 Hit到達: `HIT_LIMIT`
- 85秒timeoutでHit数差あり: `TIMEOUT`
- 85秒timeoutでHit数同点: `TIMEOUT_DRAW`
- Round境界切断不戦敗: `DISCONNECT_FORFEIT`

server → client通知:

```text
RoundResultEvent
- round_number
- winner_user_id       # Draw時は空
- loser_user_id        # Draw時は空
- finish_cause
- winner_hits
- loser_hits
- is_draw
- server_tick
```

初期 `round_number` は1とする。次ラウンド開始時のincrementはBO3実装で接続する。

`winner_hits / loser_hits` はResult確定tick時点のauthoritativeな現在ラウンドHit数を使用する。Drawでは両値が同値で、`winner_user_id / loser_user_id` は空、`is_draw=true` とする。

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

キャラクター選択の単位は `CharacterDefinition` 1件であり、頭部・髪型・アホ毛を別slotとして組み替えない。
`head_asset` と `ahoge_asset` は同じCharacterDefinitionへ固定で紐づく一体のvisual setである。
UI-04はCharacterDefinitionを選ぶ画面であり、アホ毛単体の装備選択UIではない。

```text
CharacterDefinition
- id
- display_name
- feature_text: String # Character Selectの1行特徴
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

### 12.2.1 Character Select用Visual Placeholder

正式な `head_asset / ahoge_asset` が未導入の間も、UI-04は文字だけのcardにしない。
visual-only component `MangaCharacterArt` を使用し、`CharacterDefinition` から次を描き分ける。

- `ahoge_type`: LONG / NORMAL / SHORTごとの長さ・curve
- `attack_type`: SWING / THROWを補助的なmotion cueとして表現
- selected detail previewではidle swayを付ける
- card内previewは静止または極小motionとし、可読性を優先する
- 顔・目・鼻・口・全身は描かず、頭頂部 + 髪 + アホ毛だけを描く
- Top Menu用の2人hero artはUI-04へ流用しない

このcomponentは見た目専用であり、Hit / Contact / action stateのauthoritative判定には使用しない。

現行テストキャラクターの `feature_text` は次を使用する。

- `LONG_TEST`: 「長いアホ毛で間合いを取るスタンダード型」
- `SHORT_TEST`: 「短いアホ毛を投げてかき回す変則型」

正式キャラクター導入時は各CharacterDefinitionで個別に置き換える。

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


### 13.3 Image-based Head / Ahoge Prototype

UI-10 Battleで、正式character asset導入前に「頭部画像 + 別アホ毛画像」の分離表示とLive2D風secondary motionを検証する。

Prototype asset:

```text
assets/characters/prototype/pink_profile/
├─ head.png
└─ ahoge.png
```

`LONG_TEST` の `CharacterDefinition` へ上記2pathを固定で紐づける。
頭部とアホ毛を別々に選択・装備する機能は追加しない。

実装:
- head: `Sprite2D`
- ahoge: subdivided `Polygon2D`
- root側segmentは固定
- tip側ほど変位量を大きくする
- idle時は複数sin波を合成して連続的にくねらせる
- HeadMotionのvelocityを入力し、移動方向と逆へ遅れてしなる
- STRIKE / CHARGING / STAGGER等のaction stateをvisual bendへ加える
- `ahoge_available=false` では画像ahogeを非表示にする
- gameplay / Contact / Hit判定には使用しない

assetが存在しないcharacterは従来のcode-draw FighterVisualへfallbackする。
これによりasset追加前のCIと、SHORT_TEST等の未素材characterを壊さない。

Checkpoint:
- 頭部とアホ毛が別resourceで表示できる
- 根元が頭部へ固定される
- idle時にアホ毛が連続的にぬるぬる動く
- 頭部の左右移動でアホ毛が遅れて追従する
- action時に揺れが増幅する

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
切断復帰は後続Issueで実装し、active Round中はdeadlineなし、Round境界のみ15秒待機とする。

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

#### 14.4.1 authoritative Round開始Countdown

M1 Human Verificationで、Round終了後の85秒reset・1本取得・次Round開始が視覚的に分かりにくいことをblocking findingとして確認したため、Round開始をserver authoritativeなCountdown stateへ分離する。

対象はRound 1を含む全Roundとする。

server stateへ次を追加する。

```text
round_countdown_active
round_countdown_start_tick
round_countdown_value
```

Countdownは30Hz server tickを基準に3秒間とし、表示値を `3 → 2 → 1 → GO` とする。

新規server event:

```text
opcode 114: ROUND_COUNTDOWN_CHANGED
- round_number
- countdown_value
- server_tick
```

`countdown_value` は `3 / 2 / 1 / 0` の整数とし、`0` を `GO!` と解釈する。

Round準備時の順序:

1. 次Round番号を確定する
2. Hit数を両者0へresetする
3. timer表示値を85へresetする
4. 両者を `ROUND_LOCKED` にする
5. `ROUND_COUNTDOWN_CHANGED(3)` を通知する
6. 1秒ごとに `2`、`1` を通知する
7. Countdown中はcombat inputを受理せず、85秒timerも進めない
8. Countdown終了tickで `ROUND_COUNTDOWN_CHANGED(0 = GO!)` を通知する
9. 同tickで `ROUND_STARTED`、Hit 0、timer 85、両者 `IDLE` を通知する
10. そのtickから85秒timerと戦闘入力を有効にする

Round終了から次Round Countdownへ移る際、前Roundの `BO3_SCORE_CHANGED` で取得Round数を先に確定する。clientはこのscoreを「1本取得」の表示正本とし、Countdownとは別表示する。

Round終了後は `Round Result表示フェーズ` を挟み、次Round Countdownへ即時遷移しない。

M1の暫定値として、Round Result表示フェーズは2秒（30Hzで60tick）とする。これはM1 Human Verification用の暫定演出時間であり、正式UIの最終演出時間を確定するものではない。

非最終Roundの順序:

1. 5 Hit / TIMEOUT / OVERTIME_HITでRound勝者を確定
2. 両者を `ROUND_LOCKED` にする
3. `ROUND_RESULT` を通知する
4. `BO3_SCORE_CHANGED` を通知し、取得Round数を更新する
5. 2秒間は戦闘入力・timer進行・次Round Countdownを開始しない
6. 2秒経過後に次Round番号へ進める
7. 次Roundの `3 → 2 → 1 → GO!` Countdownを開始する
8. `GO!` と同tickで戦闘と85秒timerを開始する

Match終了Roundでは次Round Countdownへ進まず、`MATCH_RESULT` へ接続する。

Countdown中に届いたclient戦闘入力は `INPUT_ACCEPTED` を返さず破棄し、input sequenceも消費しない。

`GO!` はserver上の入力解禁と同じtickを表す。clientは視認性のため `GO!` 表示を短時間残してよいが、その間もserver timerは開始済みとする。

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

Friend Matchのroom lifecycleはNakama TypeScript Runtimeを正本とし、クライアントはroom codeからmatch IDを生成・推測しない。

#### 15.2.1 Room code

- ホストがroomを作成した時点でserverが6文字codeを生成する
- 文字集合は `ABCDEFGHJKLMNPQRSTUVWXYZ23456789`
- 曖昧な `0/O/1/I` は使用しない
- secure random bytesから各文字を選ぶ
- Storageのcreate-only version checkでcode予約を行い、既存codeとの衝突時は別codeを再生成する
- roomが終了・失効したcodeはjoin不可とする

#### 15.2.2 Room Storage

```text
collection = friend_room
user_id    = system
key        = <room_code>

value:
- room_code
- host_user_id
- guest_user_id
- host_character_id
- guest_character_id
- host_ready
- guest_ready
- state
- current_match_id
- match_generation
- created_at_unix_ms
- last_activity_at_unix_ms
- expires_at_unix_ms
```

room stateは次を使用する。

```text
WAITING  # hostのみ。初回または前Match終了後の次Guest待ち
LOBBY    # host/guestが入室しCharacter Select / Ready待ち
STARTING # 両者Ready成立後、authoritative match生成中
IN_MATCH # Friend authoritative match進行中
```

放置roomは最後の有効なroom更新から2時間で失効する。status readだけでは失効時刻を延長しない。失効roomをread/joinした場合はserverが失効として拒否し、可能な場合はStorageを削除する。

#### 15.2.3 Lobby / Ready

- roomにはhost 1名、guest 1名だけ参加できる
- host/guestは自分の `character_id` だけ更新できる
- character変更時は自分のReadyを解除する
- 両者が入室し、両者が対応characterを選択した後にReady可能とする
- 両者Readyが成立した1回の状態遷移だけがauthoritative match生成を開始する
- match生成中は `STARTING` とし、重複Readyによる二重match生成を防止する
- 生成するmatchは既存 `ahoge_ranked` handlerを戦闘コアとして再利用し、`matchMode=friend` を渡す
- expected user ID / character IDはroom Storageを正本としてmatch init paramsへ渡す
- clientはroom statusでserver確定 `current_match_id` を受け取り、そのIDへjoinする

#### 15.2.4 Rating / Ranking

Friend Matchは `matchMode=friend` とし、Match Resultが確定しても次を更新しない。

- Player Rating
- PLAYER Ranking
- AHOGE LEGEND Ranking

Round / BO3 / Reconnect / Match ResultはRankedと同じserver authoritative battle handlerを使用する。

#### 15.2.5 Result / Rematch

Match Result確定時、serverは対応roomを `POST_MATCH` へ移し、Host / Guest membershipと両者のcharacterを保持する。Readyは両者falseへ戻す。Result画面の次戦方針の選択権はHostだけが持つ。Guestは「ホストの選択を待っています…」と自分自身の「ルームを抜ける」だけを持ち、Hostの選択を待つ。

Host Result操作はserver RPCを正本とし、次の3択とする。

```text
再戦する              (action=rematch)
キャラクターを選び直す (action=change_character)
ルームを終了           (action=leave)
```

- `REMATCH`
  - 現在のHost / Guestを維持する
  - 両者のcharacterを変更しない
  - Lobby / Character Selectを挟まず、同じ2人・同じcharacterで新しいauthoritative Friend matchを生成する
  - Guest Resultはroom stateが `IN_MATCH` になったことを検知して同じ新matchへjoinする
- `CHANGE CHARACTER`
  - Hostだけが選択できる
  - 現在のHost / Guest membershipは維持する
  - 両者のcharacterを未選択へ戻す
  - roomを同じroom codeの `LOBBY` へ戻す
  - Host / GuestともFriend Lobbyへ戻り、両者がCharacterを選び直す
- `LEAVE ROOM`
  - Hostだけが選択できる
  - roomを削除してcodeを無効化する
  - Host / GuestともTop Menuへ戻る

Host / GuestともResult表示中は500ms程度でroom statusをpollする。

Result表示とroom同期の順序契約:

- authoritative Match Resultを受信した時点でResult画面を即表示する。Friend roomのPOST_MATCH反映完了を画面表示の前提にしない
- Result画面表示直後はroom同期中として操作ボタンを一時非活性にしてよいが、Loading専用画面で待機し続けない
- roomが終了した旧match IDのまま `IN_MATCH` の場合はsettlement反映待ちとしてResult画面を維持する
- `IN_MATCH` をREMATCH確定と判断するのは、roomの `current_match_id` がResultの旧 `match_id` と異なる場合だけ
- `POST_MATCH` と自分のactive result ack完了を確認したらHostの3択とGuestのLEAVE ROOMを活性化する。room settlementだけ先行した瞬間にREMATCHを送らない
- HostがResult操作を1つ選択した時点で3ボタンを即時非活性化し、同じResult actionの二重送信を防ぐ。server拒否時は最新room stateを再取得して操作可否を復元する

- `POST_MATCH` → Host選択待ちを継続
- `IN_MATCH + current_match_id` → REMATCH確定として新Friend matchへjoin
- `LOBBY` → CHANGE CHARACTER確定として両者Lobbyへ戻る
- `WAITING` → GuestがResultから退出した状態。HostはLobbyへ戻って次Guest待ち
- room not found / expired → Host LEAVE ROOM確定としてTop Menuへ戻る

GuestはResultの選択操作RPCを送信できない。ただしGuest自身の `LEAVE ROOM` は許可し、Guestだけをroomから外してTop Menuへ戻す。その場合Host roomは `WAITING` へ戻り、HostはLobbyへ遷移する。空いたGuest枠は前Match参加者かどうかに関係なくroom code JOINの先着順とする。

Host以外のclient判断でREMATCH / CHANGE CHARACTER / room全体終了を確定しない。

#### 15.2.6 Leave / room終了

- active matchが `STARTING / IN_MATCH` の間はroom leave/closeで対戦結果を独自確定しない
- active match中の意図的退出・両者同時切断・server障害の勝敗契約は #71 の責務とし、本Issueでは追加しない
- guestがLobbyで退出した場合はguest slotを空け、roomを `WAITING` へ戻す
- hostがLobby / WAITINGで退出した場合はroomを終了し、Storageを削除してcodeを無効化する
- room終了後のcodeではjoinできない

#### 15.2.7 Reconnect / 未解決match lock

Friend matchへjoinした後は既存 Nakama `user_id` 単位のserver-side `active_online_match/current` に `match_mode=friend` として保持する。

- 進行中Friend matchもRankedと同じく、active Round中はdeadlineなしで同一matchへ復帰し、Round境界のみ15秒待機する
- 終了済みFriend matchへ再ログインした場合はserver result snapshotからFriend Resultへ復帰する。Result初回表示前に `ahoge_friend_room_status` で現在userのHost / Guest membershipを復元し、Hostは3択、GuestはHost選択待ち + 自分の退出操作を最初の表示から正しく出す。すでにHost選択が確定済みならroom stateへ追従する。room statusを一時取得できない場合は誤ったroleの操作を表示せず、操作無効の同期状態から再取得する
- 未解決match contextがある間、`OnlineSession` は新しいFriend room作成・参加・対戦開始を拒否する
- Match Not Found / Invalid Match IDの安全解除契約を変更しない

#### 15.2.8 RPC

初期Friend Match基盤では次のserver RPCを使用する。

```text
ahoge_friend_room_create
ahoge_friend_room_join
ahoge_friend_room_status
ahoge_friend_room_character
ahoge_friend_room_ready
ahoge_friend_room_result_action
ahoge_friend_room_leave
```

RPCはすべて認証済みuserのみ利用可能とし、room membership / room state / character ID / code形式をserverで検証する。`ahoge_friend_room_result_action` はHostだけが `rematch / change_character / leave` を確定できる。Guest自身の退出は従来の `ahoge_friend_room_leave` を使用する。

#### 15.2.9 UI-06〜08 client契約

Friend UIはserver room responseだけを状態正本とする。

```text
UI-03 Battle Mode
→ UI-06 Friend Match Menu
   ├─ CREATE ROOM
   │   → ahoge_friend_room_create
   │   → UI-08 Lobby
   └─ JOIN ROOM
       → UI-07 Room Code
       → ahoge_friend_room_join
       → UI-08 Lobby
```

UI-08は500ms間隔を目安に `ahoge_friend_room_status` をpollし、次を表示する。

- `room_code`
- `role`
- host / guest user
- host / guest character
- host / guest ready
- room `state`

Lobbyのclient操作:

- CHARACTER SELECT → 共通UI-04をFriend modeで開く → `ahoge_friend_room_character`
- READY / CANCEL READY → `ahoge_friend_room_ready`
- LEAVE ROOM → `ahoge_friend_room_leave`
- COPY → OS clipboardへroom codeをコピーするだけでserver状態は変更しない

Host / Guest退出契約:

- HostがWAITING / LOBBYでLEAVEするとroomを閉じる
- GuestはLobby pollでserverから `friend room not found` / `friend room expired` / `friend room membership required` を受けた場合、roomが継続不能になったterminal状態として扱い、local room contextを破棄してFriend Menuへ戻る
- Host closeとGuestのLEAVE操作が競合し、Guestのleave RPCが同じterminal状態を返した場合も「すでに退出済み」とみなしFriend Menuへ戻る
- timeout / network error / parse errorなどroom存在有無を確定できない失敗ではlocal room contextを破棄せずLobbyに留まり、pollを継続する

clientは「両者Readyだから開始」と独自判定しない。server responseが `state=IN_MATCH` かつ `current_match_id` を持った時だけ `join_friend_match_from_room` を実行する。

Friend matchの `MATCH_SNAPSHOT` とserver-side result snapshotには次を追加する。

```text
friend_room_code
friend_match_generation
```

これによりclient再起動 / reconnect後も、server authoritative snapshotから元Friend roomを復元できる。

Friend再起動復帰のidentity契約:

- Device認証の `device_id` は同一インストールで永続化し、再起動後も同じ値を使用する
- 同じ `device_id` で再認証したclientは同じNakama `user_id` として扱う
- Friend match中にclientが終了してもserver-side `active_online_match/current` とそのMatch参加資格は解除しない。再起動後は元authoritative matchへ復帰する
- 再起動時は新規Friend導線へ進む前に `active_online_match/current` を確認し、ACTIVEなら元authoritative matchへ強制復帰する
- RESULT_PENDINGならserver result snapshotを取得した後、Friend Resultを表示する前にroom stateを1回取得してHost / Guest roleを復元する。そのroleを初回UIへ渡し、以後はroom stateのpollでHost選択待ちまたは確定済み遷移へ追従する
- Friend roomのhost / guest membershipはNakama `user_id` を正本とし、Match終了時のPOST_MATCHでは両者membershipを保持する
- Guest自身がLEAVEした場合だけGuest枠を解放し、その空席はroom code JOINの成功順で確定する。前MatchのGuestだったかどうかは優先条件にしない
- 別 `device_id` は別userであり、進行中Matchの参加資格を引き継がない

ローカル2client Human VerificationではP1/P2が同一 `user://` を共有し得るため、P2専用helperで別Device IDを一度だけ生成・保存し、再起動時も必ず同じP2 Device IDを再利用する。これにより実製品の「同一インストール再起動」を再現する。

Friend matchのUI-09 / UI-10はRankedと同じSceneを再利用するが、`match_mode` を表示・遷移の正本とする。

- `ranked` → 従来のRating settlement付きUI-11
- `friend` → Friend Result。Player/Ahoge Ratingを表示しない

Friend Result:

- WIN / LOSE / DRAW
- 最終BO3 score
- `フレンド対戦 / レート変動なし`
- Host: `再戦する` / `キャラクターを選び直す` / `ルームを終了`
- Guest: `ホストの選択を待っています…` / `ルームを抜ける` のみ。Host専用の再戦 / キャラクター選び直し / room全体終了はGuest画面ではvisibleにしない

Result操作はHostだけが行い、server room stateを通してGuestへ伝播する。GuestはHostの選択へ追従する。

終了済みFriend matchから再ログインした場合も、server result snapshotとroom stateを正本にResult文脈を復元し、Host選択待ちまたは確定済み遷移へ接続する。

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


Season判定はserver共通 `SeasonService` を正本とする。

```text
season_id_at(unix_ms):
  shifted = unix_ms + 9時間
  YYYY-MM = shiftedをUTC年月として読む
```

境界例:

```text
2026-09-30T14:59:59.999Z = 2026-09-30 23:59:59.999 JST → 2026-09
2026-09-30T15:00:00.000Z = 2026-10-01 00:00:00.000 JST → 2026-10
```

Season metadataはNakama Storageへ保持する。

```text
collection: ranking_season
user_id: system
key: <season_id>

value:
- season_id
- starts_at_unix_ms  # その月1日 00:00:00.000 JST
- ends_at_unix_ms    # 翌月1日 00:00:00.000 JST、exclusive
```

`state` は保存値にせず、現在の `season_id` と比較して次をresponse時に導出する。

- 現在月: `CURRENT`
- 過去月: `HISTORICAL`

これにより月替わり時に過去metadataのstate更新処理を必要としない。

現在SeasonのRating / AHOGE集計は新しいseason_idのStorage key / leaderboard IDへ切り替える。前SeasonのStorage / leaderboardは削除・上書きしない。

- 新Seasonでplayer recordが未作成ならRating 1500 / wins 0 / losses 0 / draws 0
- 新SeasonでAHOGE recordが未作成ならAhoge Rating 1500 / total_match_wins 0 / total_ranked_matches 0

#### 16.1.1 月末締めと公開制御

旧Seasonランキングは最終日の23:00 JSTから翌月8:00 JSTまで非公開とする。

```text
月末 23:00
  → 旧Season Rankingを非公開

翌月 00:00
  → 新Season開始
  → 新Season Rankingは通常公開
  → 旧Seasonだけ引き続き非公開

00:00〜08:00
  → 00:00より前に開始した旧Season対象Matchの終了・settlement猶予

翌月 08:00
  → 旧Season最終Rankingを公開
```

PLAYER RankingとAHOGE LEGEND Rankingの両方へ同じ公開制御を適用する。非公開期間の旧Season Ranking RPCはrecordsを返さず、`ranking_public=false` と `ranking_hidden_until_unix_ms` を返す。新Seasonは0:00以降通常取得できる。

Matchの集計先Seasonは、**Match開始時刻だけ** からserverが決定する。

- 0:00より前に開始 → 終了時刻に関係なく旧Season
- 0:00ちょうど以降に開始 → 新Season
- 旧Season対象Matchが0:00を跨いで終了しても旧Seasonへsettlementする
- Match終了時刻によるSeason振り替えは行わない

期待勝率の計算入力と集計先SeasonはともにMatch開始時点を基準とする。

- 計算入力: Match開始時に固定したPlayer Rating / Ahoge Rating snapshot
- 集計先: Match開始時刻が属するSeason
- settlement時は対象Seasonの現在Storage Ratingへ今回Matchのdeltaだけを適用する
- 新Season開始後も、0:00前開始Matchのdeltaは旧Seasonへ反映する

settlement objectはMatch開始時snapshotのSeasonと実際の集計先Seasonを保持する。通常は同一Seasonとなる。

PLAYER Ranking / AHOGE LEGEND Ranking取得RPCはpayloadの `season_id` を任意指定できる。

- 未指定: 現在Season
- 指定: JSON文字列の `YYYY-MM` 形式を検証し、そのSeasonを取得
- `season_id` keyを明示した場合、空文字・null・boolean・numberなど `YYYY-MM` 文字列以外は拒否する
- 現在より未来のseason_idは拒否
- 過去Season指定時も現在Seasonのデータを変更しない

Season metadata取得RPCを用意し、現在 / 過去Seasonの境界とstateをclientが参照できるようにする。
境界検証・履歴参照用にread-onlyの `at_unix_ms` を任意指定できる。指定時はその時刻が属するseason_idを解決する。現在時刻より未来の `at_unix_ms` は拒否する。

### 16.2 プレイヤーランキング

個人プレイヤー単位のランキングとする。

PLAYER Rankingの順位決定値は `Rating` のみとする。wins / losses / 勝率をsecondary tie-breakへ使用しない。

同じRatingのplayerは同じ表示順位とする。

```text
1  1600
2  1550
2  1550
4  1516
```

server保存はseason単位のauthoritative Nakama leaderboardを使用する。

```text
leaderboard_id = player_rating_<YYYY-MM>
authoritative  = true
sort           = desc
operator       = set
score          = Rating
subscore       = 0
```

Rating settlement成功後、winner / loserのleaderboard recordをserver runtimeだけが更新する。leaderboard書込が一時失敗した場合、既存の `player_season_rank` Storageから再同期してretryできる構造とする。

PLAYER Ranking取得RPCは当月leaderboardの先頭から最大100件を返す。

```text
season_id
records[]
- display_rank
- player_id
- player_name
- rating
- rank_tier
- wins
- losses
- draws

response:
- season_id
- records
- rank_count
- ranking_public
- ranking_hidden_until_unix_ms
```

Nakama内部の同score record順序は表示順位に使用せず、response生成時に同Ratingを同じ `display_rank` へ正規化する。

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

キャラクター単位の月次Ahoge Ratingランキングとする。

AHOGE LEGEND Rankingは個別 `character_id` 単位で集計し、順位決定値は **Ahoge Ratingのみ** とする。

- LONG / NORMAL / SHORTは戦闘タイプでありランキング単位ではない
- タイプ別ランキングは作らない
- 同Ahoge Ratingは同じ `display_rank`
- `total_match_wins / total_ranked_matches` は参考統計でありtie-breakへ使用しない
- mirror matchはAhoge Rating ±0
- 異character matchはserver authoritativeなAhoge Rating settlementを使用する

server保存はseason単位のauthoritative Nakama leaderboardを使用する。

```text
leaderboard_id = ahoge_legend_<YYYY-MM>
authoritative  = true
sort           = desc
operator       = set
owner_id       = stable character owner UUID
score          = ahoge_rating
subscore       = 0
metadata:
- season_id
- character_id
- total_match_wins
- total_ranked_matches
```

Nakama leaderboard record ownerはUUIDが必要なため、各正式characterへ安定したserver管理owner UUIDを割り当てる。character_idとowner UUIDの対応表はserver configで一元管理し、player IDと混同しない。

AHOGE集計のStorage object自体はcharacter owner UUIDをuser_idへ流用せず、system ownerを使用する。

```text
collection = ahoge_season_rank
user_id    = system
key        = <season_id>:<character_id>
value:
- season_id
- character_id
- ahoge_rating
- total_match_wins
- total_ranked_matches
```

leaderboard owner UUIDはランキングrecordの安定owner識別だけに使用する。

Ranking RPC response:

```text
season_id
records[]
- display_rank
- character_id
- ahoge_rating
- total_match_wins
- total_ranked_matches
- legendary
rank_count
ranking_public
ranking_hidden_until_unix_ms
```

clientは `display_rank / ahoge_rating / legendary` をserver確定値として表示し、勝数・対戦数から順位やRatingを再計算しない。

旧Seasonの公開制御はPLAYER Rankingと共通とする。

- 月末23:00 JSTから旧Seasonを非公開
- 翌月00:00 JSTから新Seasonを通常公開
- 旧Season最終結果は翌08:00 JSTに公開
- 非公開応答は `records=[] / ranking_public=false / ranking_hidden_until_unix_ms=<08:00>`

### 16.4 UI-12 client契約

Godot clientは次のRPC wrapperを `OnlineSession` に持つ。

```text
get_season_metadata(season_id = "")
get_player_ranking(limit = 20, season_id = "")
get_ahoge_legend_ranking(limit = 20, season_id = "")
```

UI-12初期実装はcurrent Seasonだけを表示し、過去Season選択UIは後続対象とする。

画面遷移:

```text
Top Menu
→ RANKING
→ UI-12
→ BACK
→ Top Menu
```

UI状態:

- LOADING: RPC待機中
- READY: server recordsを表示
- EMPTY: 公開中だがrecordsが0件
- FINALIZING: `ranking_public=false`
- ERROR: 認証 / RPC / response parse失敗

PLAYER / AHOGE LEGENDタブ切替時は対応するserver Ranking RPCを取得し直す。Season labelはserver responseの `season_id` を正本とし、clientローカル時計からSeasonを推測しない。

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

切断・再接続はserver authoritativeなmatch stateを正本とする。

- active Round中に片側が切断してもRoundを停止しない
- active Round中は切断からの経過時間に関係なく、そのRoundが終了するまで再接続を許可する
- Round境界で片側が未接続の場合だけ15秒の復帰待機を開始する
- Round境界の15秒以内に復帰すれば対象Roundを通常開始する
- Round境界の15秒以内に復帰しなければ、その対象Roundだけを接続中playerの不戦勝・切断playerの不戦敗として処理する
- 不戦勝で2本先取に到達した場合は通常BO3としてMatchを終了する
- 不戦勝後もMatch未決着なら、次Roundについて新しい15秒deadlineを開始する
- active Round中の通常結果で切断playerが2本先取した場合は、そのMatch Winを有効とする
- server障害や両者同時切断は別途エラー終了として扱い、Rating更新を行わない方向で実装する

#### 21.5.1 片側切断時のactive Round進行

Round進行中に片側だけが切断した場合、match全体は停止しない。

- 85秒timerは継続する
- Overtimeも通常ルールで進行する
- 接続中playerは通常どおり入力できる
- 切断playerは新規inputを送信できない
- 切断前にserverが受理済みのWINDUP / STRIKE / COOLDOWN / Defense / Stagger / SHORT Regrow等はserver tick基準で通常どおり進行する
- 切断を理由に受理済みactionを巻き戻さない
- 接続中playerから切断playerへの有効Hit判定もserver authoritativeに継続する
- 切断中playerは無防備扱いとし、DefenseResultは常に `NONE` とする
- 切断前にPARRY / DODGEがactiveだった場合でも、切断後に到達したContactでは防御成立させない
- 切断前にserverが受理済みの攻撃actionは従来どおり進行し得るが、防御能力だけはpresence喪失時点で無効化する
- active Round中は15秒deadlineを開始しない

同じRound中に切断playerが復帰した場合、経過秒数に関係なく再joinを許可し、最新authoritative snapshotへ同期してそのRoundを継続する。

#### 21.5.2 Round境界の復帰待機

Round境界は「前Round Result」と「次Round開始側」を明確に分離する。

```text
前Round戦闘
→ 前Round Result hold
→ 次Round開始側へ切替
→ 相手接続状態確認
   ├─ 接続済み → Countdown / Round開始
   └─ 未接続 → ここから15秒reconnect deadline
```

- Countdown中に片側が切断した場合はCountdownを停止し、その対象Roundの開始側で15秒待機へ入る
- Round進行中の切断後、そのまま5 Hit / TIMEOUT / OVERTIME_HITでRoundが終了した場合、まず前Round Result holdを通常どおり完了する
- Round Result hold中は15秒deadlineを開始せず、待機時間を消費しない
- Round Result hold中に切断した場合も、deadline開始はResult hold完了後まで遅延する
- Result hold完了後にRound番号・Hit数・戦闘状態を次Round開始側へ切り替える
- その時点で未接続playerがいる場合、未接続playerごとに15秒のreconnect deadlineを開始する
- deadline前に全expected playerが復帰した場合、authoritative snapshot同期後にdeadlineを削除し、その対象RoundのCountdownから通常開始する
- clientの待機カウント表示は表示専用であり、0到達を勝敗判定には使用しない
- Match自体が通常BO3で終了した場合は次Round開始側へ移行せずMatch Resultを確定する

#### 21.5.3 Round境界15秒timeout

片側だけが未接続のままRound境界reconnect deadlineへ到達した場合、server authoritativeに**その対象Roundの不戦敗**を確定する。Match全体を直接強制敗北にはしない。

- Round finish cause: `DISCONNECT_FORFEIT`
- 接続中playerをそのRoundのwinner、deadline超過playerをそのRoundのloserとする
- 対象RoundのHit数は0-0として扱い、通常の戦闘入力やHit判定は行わない
- 不戦勝Roundを通常のBO3 Round取得数へ+1する
- 不戦勝で2本先取に到達した場合は `match_finish_cause=BO3` としてMatch Resultを確定する
- 不戦勝後も2本先取でなければ、次Roundへ進み、切断playerが未復帰なら改めて新しい15秒deadlineを開始する
- 例: 0-1で相手未接続 → 15秒timeout → 1-1 → 次Roundについて再度15秒待機 → 再timeout → 2-1で接続中playerのMatch Win
- active Round中に切断playerが通常ルールでRoundを取り、それが2本目なら15秒待機を挟まずそのMatch Winを有効とする
- clientは不戦敗を独自判定せず、serverのRound Result / BO3 Score / Match Resultを正本とする

15秒は前Round Result hold完了後に次Round開始側へ切り替わってから始まる「これから開始する1Round」の出場待機期限であり、active Round中の復帰期限でもclientのretry終了期限でもない。

deadline超過後に切断playerが戻った場合、Match未決着なら最新authoritative snapshotへ同期して次の待機中Roundから復帰する。すでに2本先取でMatch終了済みならserver-side `RESULT_PENDING` の確定Resultを取得する。

#### 21.5.4 再接続成功時の同期

serverは切断でplayer stateを破棄しない。presenceだけを切断状態へ変更する。

少なくとも次をmatch stateとして保持する。

- match ID
- match mode
- character ID
- Round番号
- Round取得数
- Hit数
- timer
- Overtime
- action state
- last input sequence
- reconnect状態
- Round境界deadline（境界待機中のみ）

同じNakama user IDが同一matchへ再joinした場合、serverは再接続playerへ最新authoritative snapshotを送信する。

clientはsnapshotを正本として現在表示・入力sequenceを更新する。切断中に受信できなかったeventをclient側で再計算・再生して追いつこうとしない。

active Round中の復帰では、切断中も進行したtimer / Hit / action stateを含む現在状態へ同期する。

#### 21.5.5 再接続待機中のフェーズ管理

serverは「active Round」「前Round Result hold」「次Round開始側」を区別する。

```text
active Round
  → 片側切断でも進行継続
  → reconnect deadlineなし
  → 同Round終了まで復帰可能

前Round Result hold
  → Result表示を完了
  → reconnect deadlineなし

次Round開始側
  → 未接続playerがいる場合だけ15秒deadline開始
  → deadline内復帰: 同一userを元matchへ再joinし、対象RoundのCountdownから通常開始
  → timeout: 対象RoundをDISCONNECT_FORFEITとして確定
```

Human Verificationでは、同一P2 userで「切断」と「15秒待機中の復帰」を再現できる必要がある。HV専用opponentは一度生成したDevice IDを一時検証用ファイルへ保持し、保存済みDevice IDがある限り上書きしない。

引数なしの既定モードは `auto` とし、同じDevice IDで認証後にserver-side `active_online_match/current` を確認する。

- `ACTIVE` がある → 同じP2 userで元matchへ自動rejoinする
- `RESULT_PENDING` がある → HV用synthetic P2の前回結果だけacknowledgeしてから新規matchmakingへ進む
- active contextなし → 同じP2 userで新規matchmakingへ進む
- `reconnect` 明示時に `ACTIVE` がない → 明示FAILする
- `new` 明示時に `ACTIVE` がある → credentialを上書きせず明示FAILする

これにより、切断後に誤って引数なしコマンドを再実行しても別P2 userへ切り替わらず、元matchへの復帰を優先する。

この一時ファイルはHuman Verification toolだけが使用する検証credentialであり、製品clientのgameplay/account状態の正本には使用しない。RESULT_PENDINGのacknowledgeもHV用synthetic P2の検証後処理に限定する。

#### 21.5.6 再ログイン時のMatch復帰

Socketの一時切断だけでなく、ゲーム終了・client crash・再起動後に同じアカウントでログインした場合も、直前のオンライン対戦へ復帰できるようにする。

未解決matchの正本はclientローカルファイルではなく、Nakama `user_id` ごとのserver-side `active_online_match/current` とする。認証成功後、現在userのactive contextをserverへ問い合わせ、通常メニュー表示より先に復帰判定を行う。

未解決matchが存在する間は次を禁止する。

- 新しいRanked Matchmaker ticket作成
- 新しいFriend room対戦開始
- 未解決matchを無視して別matchへjoinすること

server-side active contextは次の状態を持つ。

```text
ACTIVE
  → match_id / match_mode を正本として同じauthoritative matchへ復帰

RESULT_PENDING
  → server確定Result snapshotを正本として結果導線へ復帰
```

復帰判定:

1. `active=false` → 通常導線
2. `ACTIVE` → Realtime接続後、同じmatch IDへjoinしauthoritative snapshotを受信
3. `RESULT_PENDING / ranked` → Battleを再表示せずUI-11 Resultへ遷移
4. `RESULT_PENDING / friend` → room roleを復元してUI-11 Friend Resultへ直接遷移
5. `ACTIVE` だがserver上にmatchが存在しない → serverがstale contextを安全解除
6. timeout / network error / server error → contextを解除せず再試行可能な状態を保持

clientは未解決matchの有無・match ID・結果をローカルファイルから推測しない。

Result画面またはFriend側の復帰先への遷移が確定した後、clientはserverへacknowledgeを送り、対応する `active_online_match/current` を削除する。それ以前にcontextを削除してはならない。

```text
Login
→ Nakama user_id確定
→ active_online_match/current をserver照会
   ├─ なし
   │    → 通常メニュー
   ├─ ACTIVE
   │    → Realtime接続
   │    → 同じmatch IDへjoin
   │    → MATCH_SNAPSHOT
   │    → Battleへ復帰
   └─ RESULT_PENDING
        ├─ ranked → UI-11 Match Result
        └─ friend → Character Select
             ↓
        遷移確定後acknowledge
        → server context削除
```

進行中matchへの復帰では、同一プロセス内Reconnectと同じauthoritative snapshotを正本とする。

終了済みmatchについては、match process自体が終了・回収された後でも復帰できるよう、server-side contextへ確定Result snapshotを保存する。Result snapshotには少なくとも次を含める。

- `match_finished=true`
- `match_winner_user_id`
- `match_finish_cause`
- `round_wins_by_user`
- `round_number`
- `character_id_by_user`
- `match_mode`

#### 21.5.7 Ratingとの関係

Rating settlementはRoundではなくMatch結果に対して1回だけ行う。

- Round 1 / Round 2 / Round 3の各Round終了ではRatingを更新しない
- 片側が2点到達したMatch Winで1match分更新する
- 両者が同時に2点へ到達したMatch Drawでも1match分更新する
- Round境界15秒timeoutで成立した不戦勝Round自体ではRatingを更新しない
- Player RatingとAhoge Ratingは別計算・別正本として扱う
- Player Ratingは同一character対戦でも通常どおり更新する
- Player RatingのDrawは実績値0.5。Rating差がある場合、高Rating側は低下し低Rating側は上昇する
- Ahoge Ratingは異character対戦だけ勝敗/Drawで更新する
- 同一character対戦では勝敗/DrawにかかわらずAhoge Ratingは±0
- Friend Matchは従来どおり両Rating非対象
- server障害 / 両者同時切断など通常のWin/Drawとして確定しない終了はRating更新しない

### 21.6 プレイヤーランキング初期値

Eloの暫定式を使用する。

```text
initial_rating = 1500
K = 32

expected(self, opponent)
  = 1 / (1 + 10 ^ ((opponent - self) / 400))

new_rating
  = round(old_rating + K * (score - expected))
```

- 勝者 `score = 1`
- Draw `score = 0.5`
- 敗者 `score = 0`
- 更新後Ratingは標準的な四捨五入で整数化する
- 通常戦闘Roundと `DISCONNECT_FORFEIT` Roundを含め、最終的に `BO3` または `BO3_DRAW` で確定したRanked MatchだけをRating更新対象とする
- Friend MatchはRating更新対象外
- server障害 / 両者同時切断など勝敗を通常確定しない終了はRating更新しない

Rating保存はNakama Storageをserver authoritativeに使用する。

```text
collection: player_season_rank
key: <season_id>
user_id: <player_id>

value:
- season_id
- rating
- wins
- losses
- draws
```

対象Seasonのオブジェクトが存在しないplayerはRating 1500 / wins 0 / losses 0 / draws 0として扱い、最初のRanked結果で作成する。

season_idはJSTの対象月を `YYYY-MM` 形式で表す。月次Season切替の完全な運用は後続Season Issueで実装するが、Rating保存keyは最初からseason単位に分離する。

clientはRating Storageへ直接writeできない。

Match Resultごとの二重更新防止:

```text
collection: ranked_match_settlement
key: <authoritative match_id>
user_id: system(00000000-0000-0000-0000-000000000000)

value:
- match_id
- season_id
- winner_user_id
- loser_user_id
- finish_cause
- settled_at_unix_ms
```

settlementが既に存在するmatchはRatingを再更新しない。

勝者Rating、敗者Rating、settlementは1回のserver-side batched Storage writeで保存する。どれか1つだけ成功する部分更新を許可しない。


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

検索幅拡大はclientのMatchmaker ticket lifecycleで実現する。

```text
0秒    ±100 ticket
10秒   old ticket取消 → ±200 ticket
20秒   old ticket取消 → ±300 ticket
30秒   old ticket取消 → ±400 ticket
40秒   old ticket取消 → ±500 ticket
50秒+  ±500 ticketを維持
60秒+  検索継続 + prolonged waiting通知
```

要件:

- 同時に有効なRanked ticketを2枚以上保持しない
- 幅拡大時は現在ticketの取消成功後に次ticketを作成する
- matched通知を受信した時点で拡大generationを停止する
- matched済みticketを後続timerが取消しない
- user cancelで拡大generationを停止する
- Realtime切断でticket stateを破棄し、拡大generationを停止する
- 未解決match lock中は新規Matchmakerを開始しない
- 最大±500到達後は10秒ごとの再作成を行わず、そのticketで検索を継続する
- 60秒到達は検索条件変更ではなくUI通知用stateとする

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
- 両者同時切断・意図的退出を含む切断例外時ルールの最終調整
- Rating方式・ランク帯の最終調整
- AWS内の具体的なリソース構成
- macOSリリース
- 画面比率の最終値

未決事項を変更する場合は、Issueで目的を明確にし、基本設計・詳細設計を先に更新してから実装する。


## 22. UI画像アセット実装

UI画像assetのfile list / naming / visual responsibilityは `docs/UI_ASSET_SPEC.md` を正本とする。

### 22.1 Component boundary

```text
TextureButton
├─ state texture
└─ fixed label TextureRect

NinePatchRect
└─ panel / frame texture

DigitNumberDisplay
└─ TextureRect[]  # digit_0.png ... digit_9.png

ImpactImageDisplay
└─ TextureRect    # fx_hit / fx_parry / sfx_doka ...

BalloonMessage
├─ NinePatchRect
└─ Label          # 可変台詞
```

### 22.2 TextureButton

button interactionはButton/TextureButtonのsignalを正本とし、画像側へlogicを持たせない。

- normal / hover / pressed / disabled textureをstateへ割り当てる
- fixed label画像はmouse filterを無効化し、入力判定をTextureButtonへ集約する
- accessibilityやdebug検証のため、action自体の識別名はnode name / signalとして保持する

### 22.3 DigitNumberDisplay

入力: non-negative integer

処理:
1. integerをdecimal stringへ変換
2. 1文字ずつ0〜9へmap
3. 対応digit textureをTextureRectへ設定
4. 必要桁数だけ表示
5. leading zeroは付けない

Battle timerでは85〜0のみを扱う。

### 22.4 ImpactImageDisplay

入力eventをasset keyへmapする。

```text
HIT        -> fx_hit
PARRY      -> fx_parry
JUST_*     -> fx_just
DODGE      -> fx_dodge
CLASH      -> fx_clash
STAGGER    -> fx_stagger
OVERTIME   -> fx_overtime
```

表示life timeはUI/UX正本の240msを初期基準とし、position / scale / rotationはvisual-onlyとする。



### 22.6 Top Menu asset implementation

UI-01は `assets/ui/top_menu/` の画像assetを直接preloadし、次のnodeで構成する。

- background: `TextureRect`
- speed lines: `TextureRect`
- logo: `TextureRect`
- menu actions: `TextureButton`
- fixed labels: button childの `TextureRect`

`TextureButton` は共通4stateを使用する。

- normal: `btn_menu_normal.png`
- hover / keyboard focus / controller focus: `btn_menu_focus.png`
- pressed: `btn_menu_pressed.png`
- disabled: `btn_menu_disabled.png`

既存navigation signalは変更しない。

- `online_battle_requested`
- `ranking_requested`
- `settings_requested`
- `exit_requested`

開発専用 `LOCAL TEST BATTLE` は通常のTop Menuへ表示しない。
必要な場合のみuser command line argument `--show-debug-menu` で表示する。

### 22.5 Asset fallback

asset制作途中にmissing textureがある場合、開発用fallbackは許可するが、#55 M3へ提出する画面ではfallbackを残さない。

- missing assetを黙ってcode drawで製品仕様へ昇格させない
- missing assetはdebug placeholderとして明示する
- final asset導入後にplaceholder pathを削除する


### 22.7 Top Menu focus / animation

UI-01のmenu buttonは、mouseとkeyboard/controllerの選択状態を1本化する。

```text
mouse_entered(button)
  -> button.grab_focus()
  -> previous focus buttonはnormalへ戻る
  -> current buttonだけfocus texture
```

buttonはVBoxContainerへ直接置かず、固定sizeのrow wrapperへ入れる。
TextureButton自体のlocal positionをTweenし、Container layoutとanimationが競合しないようにする。

初期値:
- focus offset x = 10px
- focus duration = 0.10s
- unfocus duration = 0.10s
- press offset x = 6px追加
- press shake = ±2px
- press total duration <= 0.12s

Top Menuでは `decor_speed_lines.png` をload/displayしない。
現在のstadium + speed-line visualはBattle assetへ移管する。
