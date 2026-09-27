# AHOGE LEGEND 製造計画

## 1. 文書情報

- 対象プロダクト: `AHOGE LEGEND`
- 統括Issue: #21
- 目的: Steam公開候補までの製造順序・工程・完了条件を一元管理する
- 上位仕様: `docs/BASIC_DESIGN.md`
- 詳細仕様: `docs/DETAILED_DESIGN.md`
- 画面仕様: `docs/SCREEN_DESIGN.md`

この文書は「何をどの順序で完成させるか」の正本とする。
仕様そのものは各設計書を正とし、未決事項をこの文書だけで確定しない。

## 2. 現在地

2026-09-27時点のmainでは次まで完了している。

- 初期設計文書
- Godot 4.7.2ローカル1対1縦切り
- 実攻撃 / Charge / Parry / Dodge / Just / Clash / Stagger / SHORT投擲・Regrowのローカル版
- 85秒 / 5 Hit / Overtime / BO3のローカル版
- Nakama 3.41.0 + PostgreSQL 16.8-alpineローカル基盤
- Godot Device Authentication
- Realtime Socket
- 2人Ranked Matchmaker
- authoritative match生成と2-client join
- input_sequence / server tick検証
- authoritative攻撃状態
- server tickからcharge ratio算出
- ContactEvent生成と両client通知
- authoritative Defense / Just / Hit / AttackClash
- authoritative Stagger
- SHORT detach / Regrow
- 工程1の2-client戦闘統合検証
- authoritative現在ラウンドHit数
- authoritative 85秒timer
- 5 Hit到達によるauthoritativeラウンド終了
- timeout時のauthoritative Hit数比較
- authoritative Overtime
- authoritative Round Result

現在は **工程2: authoritativeラウンド・BO3** の途中で、2本先取BO3を実装中である。

## 3. 製造工程

| 工程 | 内容 | 統括Issue | 状態 |
| --- | --- | --- | --- |
| 0 | 設計・ローカル縦切り・オンライン基礎 | #1〜#19 | 完了 |
| 1 | オンライン戦闘コア | #22 | 完了 |
| 2 | authoritativeラウンド・BO3 | #23 | 進行中 |
| 3 | オンラインサービス | #24 | 未着手 |
| 4 | GameFlow・主要12画面 | #25 | 未着手 |
| 5 | 正式キャラクター・演出・素材 | #26 | 未着手 |
| 6 | AWS・Steam・Windows・WAN QA | #27 | 未着手 |
| 7 | Release Candidate | #28 | 未着手 |

### 3.1 実画面目視マイルストーン

機能実装と自動試験だけを連続して進め、最後に初めて実画面を確認する進め方は禁止する。

目的は、完成後に大きな認識差・操作感の問題・画面設計の破綻が発覚して大規模な手戻りになることを防ぐことである。

マイルストーンは通常の自動試験とは別の **blocking Human Verification** とする。各マイルストーンでは必ずGodotの実ウィンドウまたは実配布ビルドを起動し、人間が実際に操作して目視確認する。

共通ルール:

- headless試験、CI、smoke PASSだけではマイルストーン完了にしない
- 実画面を起動し、操作感と見た目を両方確認する
- 静止状態はスクリーンショット、動きが重要な箇所は短い画面録画を証跡として残す
- 設計意図との大きな乖離、操作しにくさ、視認性問題、画面遷移の違和感があれば次工程へ進まない
- 問題を見つけた場合は修正Issueを作り、必要なら BASIC / DETAILED / SCREEN DESIGN を先に更新してから修正する
- マイルストーンPASS後も、最終Human Verificationを省略しない

| Milestone | 実施位置 | 主な確認対象 | Issue |
| --- | --- | --- | --- |
| M1 Battle Core | 工程2完了直後 | UI-10 Battle、戦闘操作、HUD、85秒、Hit、Round / BO3、Overtime | #53 |
| M2 Ranked主要導線 | 工程4前半 | TOP → Ranked → Character Select → Matching → Battle → Result | #54 |
| M3 主要12画面 | 工程4完了時 | UI-01〜UI-12、Ranked / Friend全導線、Loading / Error | #55 |
| M4 正式キャラクター初回品質 | 工程5前半 | 最初の正式キャラ、頭部・アホ毛、Motion、VFX、SE | #56 |
| M5 実配布環境 | 工程6完了時 | Windows x86_64、AWS、Steam、WAN、実解像度・実通信 | #57 |


## 4. 工程1: オンライン戦闘コア

目的は、ローカルで成立している戦闘ルールをNakama authoritative matchへ移管し、2クライアントが同じ戦闘結果を受信する状態にすること。

実装順:

1. authoritative DEFEND
2. Parry / Dodge
3. Just Parry / Just Dodge
4. 攻撃中Defense cancel
5. Contact → Hit / Defense / Clash
6. Stagger
7. SHORT detach / regrow
8. 2-client戦闘統合検証

完了条件:

- 攻撃・防御・ジャスト・相殺・Stagger・SHORT状態をserverが確定する
- 2クライアントで同じ戦闘結果になる
- 見た目の擬似物理はGodot側に残す

## 5. 工程2: authoritativeラウンド・BO3

実装順:

1. server Hit数
2. 85秒timer
3. 5 Hitラウンド勝利
4. timeout時のHit数比較
5. Overtime
6. Round result
7. 2本先取BO3
8. Match result

完了条件:

- Match StartからMatch Resultまでserverだけで勝敗を確定できる
- 2クライアントのRound / Match結果が一致する

### 工程2完了ゲート: M1 Battle Core

工程2のserver実装が完了したら、工程3へ進む前に #53 を実施する。

この時点では工程4の全GameFlow完成を待たない。UI-10へ直接入れる最小のデバッグ導線を用意し、authoritativeなBattle状態を実画面へ接続して確認する。仮素材・仮レイアウトでよいが、実際に操作できることを必須とする。

M1で重大な乖離が見つかった場合、工程3へ進む前に修正する。

## 6. 工程3: オンラインサービス

実装順:

1. Matchmaker検索幅を10秒ごとに±100拡大
2. 最大±500
3. 60秒以降の待機継続
4. 15秒切断・再接続
5. Elo Rating
6. PLAYER Ranking
7. AHOGE LEGEND Ranking
8. 毎月1日0:00 JSTのSeason切替
9. 過去Season保持
10. Friend room code / Friend Match

完了条件:

- Ranked / Friendが両方成立する
- FriendはRating非対象
- PLAYER / AHOGE LEGEND両ランキングが月次Seasonで動作する

## 7. 工程4: GameFlow・主要12画面

`docs/SCREEN_DESIGN.md` のUI-01〜UI-12を実機能へ接続する。

工程4は全12画面を一気に作り切らない。まずRankedの主要導線を完成させ、M2で方向性を確認してから残画面へ進む。

工程4内の順序:

1. UI-01 / UI-03 / UI-04 / UI-05 / UI-09 / UI-10 / UI-11 を実機能へ接続
2. #54 M2 Ranked主要導線を実画面で確認
3. UI-02 / UI-06 / UI-07 / UI-08 / UI-12 とFriend導線を接続
4. Loading / Error / Back / Decide / Cancel等の共通挙動を統合
5. #55 M3 主要12画面・全導線を実画面で確認
6. M3 PASS後に工程5へ進む

主な通し導線:

```text
起動
→ ONLINE
→ RANKED / FRIEND
→ Character Select
→ Matchmaking / Lobby
→ PreBattle Dialogue
→ Battle
→ Match Result
→ Ranking / Rematch / Next Match
```

初期段階は機能・遷移・状態表示を優先し、見た目の仕上げを先行させない。

ただし仮UIだから目視確認を省略してよいという意味ではない。M2 / M3では仮UIの段階で、画面構造・視線誘導・操作導線・情報量・5:4戦闘領域案を確認する。

## 8. 工程5: 正式キャラクター・演出・素材

実装・制作対象:

- 正式初期キャラクター
- LONG / NORMAL / SHORTと攻撃タイプ
- CharacterDefinition
- 頭頂部・アホ毛の新規描き起こし
- MotionProfile
- BGM / SE / VFX
- 対戦前掛け合い
- 勝利台詞
- 権利状態管理

工程5は、全正式キャラクターをまとめて量産しない。

1. 代表となる最初の正式キャラクターをCharacter Select / Battleへ組み込む
2. 可能ならLONG系とSHORT系を各1体まで先行して、頭部・アホ毛・Motion・VFX・SEを確認可能にする
3. #56 M4 正式キャラクター初回品質を実画面で確認
4. M4 PASS後に残りキャラクター・演出・素材を量産する

未決事項は人間の判断を得てから設計へ反映する。
`PENDING`素材は公開ビルドへ含めない。

## 9. 工程6: AWS・Steam・Windows・WAN QA

実装・検証対象:

- AWS東京のNakama / PostgreSQL
- secret管理
- migration / backup
- Steam Authentication
- Windows x86_64 export
- 2地点WAN対戦
- latency / packet loss / disconnect / reconnect
- 長時間試験
- performance / balance調整

macOSは対応可能であれば維持する。

工程6の完了時には #57 M5 を実施する。
Windows x86_64の実ビルド、AWS東京、Steam認証、2地点WANを使い、実際の画面を起動してMatchmaking → Battle → Resultまで通し確認する。

M5で重大な表示・操作・通信問題が残る場合はRelease Candidateへ進まない。

## 10. 工程7: Release Candidate

```text
RC1
→ full regression
→ blocking修正
→ RC再生成
→ 最終Human Verification
→ Steam公開候補
```

公開候補確定前に少なくとも次を確認する。

- Ranked
- Friend
- Ranking / Season
- 全正式キャラクター
- Steam認証
- AWS
- Windows x86_64
- WAN
- 公開アセット権利状態
- blocking不具合0

## 11. 当面の一本道

現在からの優先順は次とする。

1. 2本先取BO3
2. Match result
3. Client Battle画面接続
4. M1 #53 Battle Core実画面確認
6. Disconnect / Reconnect
7. Matchmaker検索幅拡大
8. Ranking / Rating / Season
9. Friend Match
10. 全画面GameFlow
11. 正式キャラクター
12. 演出・音・台詞
13. Steam認証
14. AWS本番
15. Windows実機・WAN試験
16. balance / performance調整
17. Release Candidate

## 12. 計画変更ルール

- 依存工程を飛ばして後工程を先行しない
- UIの見た目だけを戦闘・GameFlowより先に作り込まない
- 未決事項を実装都合で確定しない
- 計画変更はIssueで理由を記録し、この文書を先に更新する
- 各実装はIssue → 設計更新 → commit → 実装 → 自動検証 → Human Verification → PR → main採用の順で進める
- 指定された実画面マイルストーンはblocking gateとし、PASSするまで次の対象工程へ進まない
- マイルストーンでは必ず実ウィンドウまたは実配布ビルドを起動し、headless試験だけで代替しない
- マイルストーンで想定との大きな乖離を発見した場合は、後工程へ進む前に設計・実装を修正する
