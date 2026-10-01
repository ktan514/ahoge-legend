# AHOGE LEGEND UI/UXデザイン

## 1. 文書情報

- 対象プロダクト: `AHOGE LEGEND`
- 統括Issue: #98
- 最終確認: #55 M3
- 上位機能画面仕様: `docs/SCREEN_DESIGN.md`
- 詳細仕様: `docs/DETAILED_DESIGN.md`
- ステータス: DESIGNING

本書は、AHOGE LEGENDの**製品版UI/UXデザインの正本**とする。

工程4までのGodot画面は機能成立を目的としたprototypeであり、現在の見た目・文言・配置・操作感を最終仕様として継承する義務はない。

## 2. デザイン工程の目的

主要12画面と共通状態について、機能仕様を維持しながら、製品として一貫した見た目・操作感・情報階層へ再設計する。

対象は単なる装飾ではなく、次を含む。

- 情報構造
- レイアウト
- typography
- color
- spacing
- component
- copy
- interaction
- feedback
- transition
- animation
- responsive layout
- Battle HUD
- Loading / Waiting / Error / Reconnect

## 3. 設計順序

### 3.1 Design foundation

以下を最初に確定する。

- visual direction / tone
- target impression
- typography hierarchy
- base color / semantic color
- spacing scale
- grid / safe area
- corner / border / shadow / panel rule
- icon style
- animation tempo
- focus / hover / pressed / disabled rule

### 3.2 Common components

最低限、次を共通componentとして設計する。

- Primary Button
- Secondary Button
- Destructive / Leave Button
- Back Button
- Tab
- Dropdown / Option
- Slider
- Toggle
- Input
- Character Card
- Player Badge
- Rank Badge
- Result Action
- Modal / confirmation
- Toast / inline status
- Loading / Waiting / Error / Reconnect

### 3.3 Copy system

画面文言もデザイン対象とする。

- 日本語 / 英語の採用方針
- button wording
- title / subtitle
- success / failure
- waiting / loading
- reconnect
- destructive action
- confirm / cancel
- technical errorをそのまま露出しないルール

### 3.4 Navigation / transition

- Back / Decide / Cancel / Leaveの役割
- screen transition direction
- modalとfull-screen transitionの使い分け
- Loadingを挟む条件
- network待ちの見せ方
- transition duration / easing
- input lock中のfeedback

### 3.5 Responsive layout

対象:

- Window
- Fullscreen
- 1280x720
- 1600x900
- 1920x1080
- 16:9 wide

Battleは5:4中央領域案を固定せず、最終UI/UX設計で採否を決定する。

## 4. Screen-by-screen design

以下はすべて最終デザイン未確定。工程4.5で順に設計する。

| ID | Screen | 最終デザイン |
| --- | --- | --- |
| UI-01 | Top Menu | PENDING |
| UI-02 | Settings | PENDING |
| UI-03 | Battle Mode Select | PENDING |
| UI-04 | Character Select | PENDING |
| UI-05 | Ranked Matching | PENDING |
| UI-06 | Friend Match Menu | PENDING |
| UI-07 | Friend Room Join | PENDING |
| UI-08 | Friend Room Lobby | PENDING |
| UI-09 | PreBattle Dialogue | PENDING |
| UI-10 | Battle / HUD | PENDING |
| UI-11 | Match Result | PENDING |
| UI-12 | Ranking | PENDING |

各画面では最低限以下を確定する。

1. purpose
2. primary action
3. secondary action
4. information hierarchy
5. layout
6. component
7. exact copy
8. state variants
9. transition in / out
10. responsive behavior
11. screenshot / mockup
12. Human Verification result

## 5. 実装ルール

- Godot実装前に対象UI/UX設計を更新する
- prototypeの座標・サイズ・文言を理由なく踏襲しない
- 見た目だけでなくinteractionとtransitionも設計対象とする
- reusable componentを優先し、画面ごとの独自ボタン乱立を避ける
- screen-specific logicとvisual componentを可能な限り分離する
- gameplay / server authoritative contractは既存設計を維持する
- UI都合でserver/gameplay仕様を暗黙変更しない

## 6. M3完了条件

#55 M3は工程4.5の最終ゲートとする。

M3ではprototypeとの比較ではなく、本書で確定した最終UI/UXに対して次を確認する。

- UI-01〜UI-12
- Ranked full flow
- Friend full flow
- Settings / Ranking
- Loading / Waiting / Error / Reconnect
- Back / Decide / Cancel / Leave
- Battle HUD
- responsive layout
- 5:4戦闘領域の最終採否
- wide screen余白
- copy
- transition / animation
- overall visual consistency

M3 PASSまでは工程5の正式素材量産へ進まない。


## 7. Visual Direction候補

### 7.1 全候補で共通する非交渉条件

AHOGE LEGENDのUI/UXは次を必ず満たす。

- 主役はキャラクター全身ではなく「頭頂部 + アホ毛」
- 画面を見た瞬間にコミカルな1対1対戦ゲームだと理解できる
- 85秒 / Hit数 / Round取得数など、対戦中の重要情報を一瞬で読める
- マウスだけで遊ぶゲームとして、hover / pressed / disabledのfeedbackを明確にする
- 配信切り抜きやSNS動画でもUIが読める
- キャラクター素材が増えてもUIの色がキャラクターを食わない
- Ranked / Friend / Result / Ranking / Settingsまで同じvisual languageで統一する
- prototypeの灰色panel / default Godot buttonを最終見た目として残さない
- 技術エラー文をそのままユーザーへ露出しない
- 16:9を基本としつつ、Battleの中央戦闘領域は視認性を優先して設計する

### 7.2 Direction A: POP ARCADE / AHOGE STICKER

#### 狙い

「一目でバカゲーっぽく、でも対戦UIは読みやすい」方向。

アホ毛そのものをロゴ・アイコン・separator・cursor・rank badge等へ反復利用し、AHOGE LEGEND固有のvisual identityを作る。

#### visual

- dark neutral background + vivid accent
- 大きく太い見出し
- sticker / badge / rounded panel
- 重要ボタンは大きく、primary / secondary / destructiveを明確に分ける
- 直線だけでなく、わずかな傾き・切り欠き・アホ毛形状をcomponentへ取り込む
- キャラクター色はplayer / character accentとして限定使用

#### draft palette

| token | draft |
| --- | --- |
| Background | #11131A |
| Surface | #1C202B |
| Surface Raised | #252B39 |
| Text Primary | #F7F8FC |
| Text Secondary | #B8C0D0 |
| Primary | #FF4F9A |
| Secondary | #38D8FF |
| Accent | #FFD84D |
| Success | #55DF91 |
| Danger | #FF6262 |

色値は方向比較用のdraftであり、採用後にcontrast検証して確定する。

#### typography

- title: 極太 / compact / 角丸寄り
- heading: 太字
- body: 可読性優先のsans
- 数値: Battle timer / Hit / Ratingはtabular数字相当の揃った見え方
- 英字タイトルは強く、日本語説明は読みやすく抑える

#### component

- Primary Button: 大きいpill / rounded rectangle、hoverで浮き、pressedで沈む
- Secondary: outlineまたは低彩度surface
- Destructive: 赤系、通常操作と明確に分離
- Tab: sticker label風
- Rank Badge: medal / sticker
- Character Card: 大きなアホ毛silhouette + name + archetype
- Loading: アホ毛が左右へしなる短いloop

#### motion

- 120〜180ms: hover / pressed
- 180〜260ms: panel enter / exit
- Result / Matching等は少し強いovershootを許容
- Battle中HUDはほぼ静的にし、重要eventだけ短く反応

#### 長所

- SNS / Steam screenshotで内容を理解しやすい
- コミカルさと対戦ゲームらしさを両立しやすい
- キャラクター素材が主役になりやすい
- 全12画面へ展開しやすい

#### リスク

- 彩度を上げすぎると安っぽく見える
- sticker感を使いすぎると情報密度の高いRanking / Settingsで騒がしくなる

### 7.3 Direction B: LIVE BROADCAST / VTUBER MATCH

#### 狙い

「配信番組の対戦コーナー」をそのままゲームUIへ持ち込む方向。

対戦前 / Matching / Ranking / Resultをbroadcast packageとして見せ、hololive fan gameらしい配信文脈を強くする。

#### visual

- dark navy / near black
- cyan / magenta / live red
- lower-third / ticker / live indicator
- thin line + glow + glass panel
- player sideをLEFT / RIGHTでbroadcast graphic化

#### typography

- title: condensed bold
- body: clean sans
- numbers: broadcast scoreboard風
- status wordingは短くuppercaseを多用

#### component

- Button: broadcast control panel風
- Tab: on-air channel selector風
- Player Badge: nameplate / lower third
- Ranking: tournament / sports standings風
- Loading: signal scan / connecting indicator

#### motion

- wipe
- slide
- ticker
- scanline的transition
- Resultはscoreboard切替風

#### 長所

- VTuber / 配信文化との親和性が高い
- Online Battle / Rankingと非常に相性が良い
- HUD設計を統一しやすい

#### リスク

- generic esports UIに寄りすぎる可能性
- コミカルな「アホ毛だけで戦う」馬鹿馬鹿しさが弱くなる
- glass / glowを多用するとキャラクターよりUIが目立つ

### 7.4 Direction C: MANGA BOUT / COMIC IMPACT

#### 狙い

「アホ毛同士の小競り合いを漫画の1コマとして見せる」方向。

対戦前掛け合い・攻撃・Parry・Resultを吹き出し / impact text / speed lineで強く見せる。

#### visual

- warm off-white / ink blackをbase
- player accentにred / blue
- yellowをimpact accent
- manga panel / speech balloon / speed line
- UIの輪郭は太く、shadowよりoutline重視

#### draft palette

| token | draft |
| --- | --- |
| Paper | #FFF6E4 |
| Ink | #181818 |
| Red | #FF5A4E |
| Blue | #438EFF |
| Impact Yellow | #FFD43B |
| Muted Gray | #D7D0C3 |

#### typography

- title: 太いdisplay
- speech / result: comic caption
- body / settings: 通常sansで読みやすさを維持

#### component

- Button: manga caption box
- Modal: speech balloon
- Result: full-frame impact panel
- PreBattle: left / right speech panels
- Battle event: JUST / PARRY / HIT等を短いimpact typographyで表示

#### motion

- panel snap
- impact scale
- speed-line reveal
- screen-shakeはごく限定的
- 通常menuは静かにし、Battle eventへ演出を集中

#### 長所

- AHOGE LEGENDの馬鹿馬鹿しさを最も強く表現できる
- PreBattle / Battle / Resultに強い個性が出る
- SNS短尺で印象に残りやすい

#### リスク

- Settings / Ranking等の静的画面へ展開する際に整理が必要
- 演出過多だと対戦中の可読性を損ねやすい
- キャラクター本体のアートstyleとの整合が重要

### 7.5 比較

| 観点 | A POP ARCADE | B LIVE BROADCAST | C MANGA BOUT |
| --- | --- | --- | --- |
| コミカルさ | 高 | 中 | 最高 |
| 対戦ゲームらしさ | 高 | 最高 | 高 |
| VTuber文脈 | 中 | 最高 | 中 |
| アホ毛固有性 | 最高 | 中 | 高 |
| Menu / Settings展開 | 最高 | 高 | 中 |
| Battle演出 | 高 | 高 | 最高 |
| Ranking適性 | 高 | 最高 | 中 |
| SNS screenshot | 最高 | 高 | 最高 |
| 実装複雑度 | 中 | 中 | 高 |
| 全12画面の統一しやすさ | 最高 | 高 | 中 |

### 7.6 暫定推奨

現時点の第一候補は **Direction A: POP ARCADE / AHOGE STICKER** とする。

理由:

- AHOGE LEGEND固有の「アホ毛そのもの」をUI identityへ使いやすい
- コミカルさを維持しながらRanked / Ranking / Settingsの情報UIも破綻しにくい
- 正式キャラクター素材を主役にできる
- 12画面全体へ同じcomponent systemを展開しやすい
- Steam screenshot / SNS短尺の双方で理解されやすい

ただしBattle / Result / PreBattleのimpact表現はDirection Cのcomic要素を部分採用できる。

暫定hybrid案:

```text
Base UI / Menu / Settings / Ranking
    = Direction A POP ARCADE

Battle event / PreBattle / Result impact
    = Direction C MANGA BOUTを限定採用

Broadcast的なscoreboard可読性
    = Direction Bから一部採用
```

最終方向はHuman Decisionで確定する。確定前にGodot本実装へ進まない。

## 8. #100 Human Decision項目

Human Decisionが必要な項目:

1. visual direction:
   - A POP ARCADE
   - B LIVE BROADCAST
   - C MANGA BOUT
   - AをbaseにB/Cを限定採用するhybrid
2. UIの主言語:
   - 日本語中心
   - 英語中心
   - title / short labelは英語、説明は日本語
3. 全体の明るさ:
   - dark base
   - light base
   - screenごとに使い分け
4. corner / component:
   - rounded
   - angular
   - mixed
5. motion:
   - restrained
   - playful
   - highly animated
