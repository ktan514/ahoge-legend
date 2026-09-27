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

現在は **工程1: オンライン戦闘コア** の途中である。

## 3. 製造工程

| 工程 | 内容 | 統括Issue | 状態 |
| --- | --- | --- | --- |
| 0 | 設計・ローカル縦切り・オンライン基礎 | #1〜#19 | 完了 |
| 1 | オンライン戦闘コア | #22 | 進行中 |
| 2 | authoritativeラウンド・BO3 | #23 | 未着手 |
| 3 | オンラインサービス | #24 | 未着手 |
| 4 | GameFlow・主要12画面 | #25 | 未着手 |
| 5 | 正式キャラクター・演出・素材 | #26 | 未着手 |
| 6 | AWS・Steam・Windows・WAN QA | #27 | 未着手 |
| 7 | Release Candidate | #28 | 未着手 |

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

1. authoritative Defense
2. Parry / Dodge / Just
3. Contact → Hit / Defense / Clash
4. Stagger
5. SHORT detach / regrow
6. 85秒 / Hit数
7. Round / Overtime
8. BO3 Match
9. Client Battle画面接続
10. Disconnect / Reconnect
11. Matchmaker検索幅拡大
12. Ranking / Rating / Season
13. Friend Match
14. 全画面GameFlow
15. 正式キャラクター
16. 演出・音・台詞
17. Steam認証
18. AWS本番
19. Windows実機・WAN試験
20. balance / performance調整
21. Release Candidate

## 12. 計画変更ルール

- 依存工程を飛ばして後工程を先行しない
- UIの見た目だけを戦闘・GameFlowより先に作り込まない
- 未決事項を実装都合で確定しない
- 計画変更はIssueで理由を記録し、この文書を先に更新する
- 各実装はIssue → 設計更新 → commit → 実装 → 自動検証 → Human Verification → PR → main採用の順で進める
