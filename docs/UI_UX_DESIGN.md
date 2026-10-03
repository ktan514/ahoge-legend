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

本節は工程4.5開始時に定めた**設計対象一覧の履歴**である。現在の最終Screen Designは §14 を正本とし、UI-01〜UI-12はすべて `DESIGN v1` 確定済みである。

| ID | Screen | 現在の設計状態 |
| --- | --- | --- |
| UI-01 | Top Menu | DESIGN v1（§14.1） |
| UI-02 | Settings | DESIGN v1（§14.2） |
| UI-03 | Battle Mode Select | DESIGN v1（§14.3） |
| UI-04 | Character Select | DESIGN v1（§14.4） |
| UI-05 | Ranked Matching | DESIGN v1（§14.5） |
| UI-06 | Friend Match Menu | DESIGN v1（§14.6） |
| UI-07 | Friend Room Join | DESIGN v1（§14.7） |
| UI-08 | Friend Room Lobby | DESIGN v1（§14.8） |
| UI-09 | PreBattle Dialogue | DESIGN v1（§14.9） |
| UI-10 | Battle / HUD | DESIGN v1（§14.10） |
| UI-11 | Match Result | DESIGN v1（§14.11） |
| UI-12 | Ranking | DESIGN v1（§14.12） |

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

## 9. 採用Visual Direction

Human Decisionにより、Direction C: MANGA BOUT / COMIC IMPACT を正式採用する。

採用理由:

- AHOGE LEGENDの「アホ毛同士が本気で戦う馬鹿馬鹿しさ」を最も強く表現できる
- PreBattle / Battle / Resultで画面映えする
- 漫画的なコマ割り・吹き出し・擬音・集中線を、ゲームの読み合いと相性よく使える
- SNS短尺 / Steam screenshotで一目で個性を出しやすい
- 頭頂部 + アホ毛だけというBattle構図を、漫画コマの切り取りとして自然に見せられる

### 9.1 採用時の制約

C案を採用するが、「常時うるさい漫画演出」にはしない。

- Menu / Settings / Rankingは整理された漫画誌面として静的・読みやすくする
- PreBattle / Battle event / Resultだけimpactを強くする
- Battle中は攻撃予備動作・アホ毛・timer・Hit数を最優先し、装飾が戦闘を邪魔しない
- 擬音や集中線は短時間表示とし、常時画面を覆わない
- character colorは補助色として使い、基本UIはPaper / Ink / Impact Yellowを軸にする
- 顔全体・全身をBattle画面へ表示しない

### 9.2 Design System draft（履歴）

Human Decision済み:
- visual direction: MANGA BOUT / COMIC IMPACT

本節はDesign System確定前のdraft履歴である。**現在の正本は §12 Design System v1 / §13 Design System確定**とし、本節の値を現行仕様として参照しない。

#### Color

| Token | Draft | 用途 |
| --- | --- | --- |
| Paper | #FFF6E4 | menu / panel base |
| Ink | #181818 | text / border / comic frame |
| Impact Yellow | #FFD43B | primary action / emphasis |
| Player 1 Blue | #438EFF | P1 / left-side identity |
| Player 2 Red | #FF5A4E | P2 / right-side identity |
| Muted Paper | #E8E0D2 | disabled / secondary surface |
| Error | #D93434 | destructive / error |
| Success | #2E9F5B | success state |

色値は方向確認用draftであり、contrast検証後に確定する。

#### Shape

- 角丸を基本形にしない
- comic panel / caption box / cut-cornerを基本とする
- borderは2〜4px相当のInk線
- shadowは柔らかいdrop shadowより、ずらしたInk影・offset shadowを優先
- Primary ActionはImpact Yellow + Ink border
- Destructiveは白地 + Error border、またはError fill
- disabledはMuted Paper + 低contrast Ink

#### Spacing

8px基準のspacing scaleを使用する。

4 / 8 / 16 / 24 / 32 / 48 / 64

- minimum safe margin: 32px
- primary content gap: 24〜32px
- section gap: 32〜48px
- click target最小高: 44px
- primary button標準高: 56px前後

#### Typography roles

フォントfamily自体は後続で権利確認して確定する。

- Display XL: logo / WIN / LOSE / comic impact
- Display L: screen title
- Heading: section title / character name
- Body: 説明 / setting label
- Caption: 状態補足 / secondary info
- Number XL: Battle timer
- Number L: Hit / Round / Rating

方針:
- displayは太い漫画見出し風
- bodyは可読性優先
- 数字は桁幅が暴れない見え方を優先
- 長文をdisplay書体で読ませない

#### Motion draft

- hover: 80〜120ms
- pressed: 60〜100ms
- screen transition: 180〜240ms
- result impact: 250〜400ms
- comic impact text: 180〜300ms
- Battle HUD常時animationは禁止
- screen shakeは重大eventだけ、2〜4px程度の短時間に限定

## 10. 代表4画面 具体デザイン（先行設計履歴）

この節は#101へ渡した先行screen designの履歴である。UI-01 / 04 / 10 / 11を含む現在の全画面仕様は §14 UI-01〜UI-12 最終Screen Design v1を正本とする。

### 10.1 UI-01 Top Menu

#### Purpose

ゲームの入口。数秒で「アホ毛で戦う対戦ゲーム」と理解でき、主要機能へ迷わず移動できること。

#### Layout

16:9基準。

    ┌──────────────────────────────────────────────┐
    │ AHOGE LEGEND logo                 version / notice │
    │──────────────────────────────────────────────│
    │                                              │
    │  ┌────────────┐      large hero manga panel │
    │  │ ONLINE     │      character / ahoge art  │
    │  │ BATTLE     │      speech / tagline       │
    │  ├────────────┤                             │
    │  │ RANKING    │                             │
    │  ├────────────┤                             │
    │  │ SETTINGS   │                             │
    │  └────────────┘                             │
    │                                              │
    │ small secondary footer / fan-game notice     │
    └──────────────────────────────────────────────┘

#### Information hierarchy

1. AHOGE LEGEND logo
2. ONLINE BATTLE
3. hero visual
4. RANKING
5. SETTINGS
6. secondary legal / version

#### Visual

- 背景はPaperを全面ベタ塗りではなく、薄いhalftone / manga panel texture
- 左側の主要menuはInkの斜めcaption box
- 現在hover中のitemだけImpact Yellowで塗る
- hero panelは漫画の大コマ
- comic decorationは右側へ寄せ、menu文字の可読性を邪魔しない
- title logo周囲に過剰な吹き出しを置かない

#### Draft copy

- ONLINE BATTLE
- RANKING
- SETTINGS
- EXIT

補足日本語はhover時または小captionとして出す。button本体は短い英語labelを基本候補とする。

#### Interaction

- hover: 黄色markerが左→右へ走る
- pressed: button panelが2〜3px沈む
- screen exit: 選択panel方向へcomic wipe
- mouse cursorが乗っただけで大きくUI全体を動かさない

#### Responsive

- 1280x720でもmenuが縦に潰れない
- hero artはcrop可
- logo / menuはsafe area内で固定
- Fullscreen / Windowでrelative位置を維持

### 10.2 UI-04 Character Select

#### Purpose

キャラクターの「見た目のアホ毛」と「戦闘個性」を比較して決める。

#### Layout

    ┌──────────────────────────────────────────────┐
    │ CHARACTER SELECT                  mode badge │
    │──────────────────────────────────────────────│
    │                                              │
    │  [card] [card] [selected large card] [card]  │
    │                                              │
    │  ┌───────────────────────────┐  ┌─────────┐ │
    │  │ selected character        │  │ AHOGE   │ │
    │  │ name / type / attack      │  │ preview │ │
    │  │ short description         │  │ motion  │ │
    │  └───────────────────────────┘  └─────────┘ │
    │                                              │
    │  BACK                         [ DECIDE ]      │
    └──────────────────────────────────────────────┘

#### Character card

- 縦長manga panel
- 顔写真一覧ではなく、頭頂部 + アホ毛形状が一目で比較できるcropを優先
- name
- Ahoge Type
- Attack Type
- selected cardのみImpact Yellow frame
- hoverでpanelが3〜5px前へ出る
- locked / unavailableはhalftone overlay

#### Selected detail

最低情報:
- Character Name
- AHOGE TYPE: LONG / NORMAL / SHORT
- ATTACK TYPE
- 1行の特徴
- Ahoge preview

数値parameterを大量表示しない。ゲーム開始前に理解が必要な差だけ見せる。

#### Draft actions

- BACK
- DECIDE

Friend Lobbyから来た場合も基本layoutは共通化し、上部mode badgeだけ変更する。

#### Transition

- card変更: 120〜180ms
- Ahoge preview: card選択時に1回だけ小さくしなる
- DECIDE: selected cardをcomic panel zoomして次画面へ

### 10.3 UI-10 Battle / HUD

#### Non-negotiable composition

Battle画面では顔・目・全身を表示しない。

表示するのは各playerの:
- 頭頂部
- 髪
- アホ毛
- 必要最小限の髪飾り

だけ。

crop lineは原則として眉・目が画面へ入らない位置とする。

#### Composition

    ┌──────────────────────────────────────────────┐
    │ P1 name / rounds / hits    85    P2 hits / rounds / name │
    │──────────────────────────────────────────────│
    │                                              │
    │              COMBAT / AHOGE SPACE            │
    │                                              │
    │           ← ahoge reach / clash →            │
    │                                              │
    │  P1 head-top                     P2 head-top │
    │  ╭──────╮                       ╭──────╮     │
    │  │ hair │╲                     ╱│ hair │     │
    │  ╰──────╯ ahoge             ahoge╰──────╯     │
    └──────────────────────────────────────────────┘

#### Head crop

- 左player頭頂部は画面左下
- 右player頭頂部は画面右下
- 頭部の見える高さはBattle field高の20〜30%程度から検証開始
- 目・鼻・口は表示しない
- アホ毛根元と髪型でキャラクター識別できること
- 頭部は攻撃・parry・dodgeに必要な範囲だけ動く
- full character portraitはHUDにも置かない方向を第一候補とする

#### HUD

Top barは漫画scoreboardとして整理する。

中央:
- 85 timerを最大
- 下に ROUND 1

左右:
- player name
- round wins
- hit count
- connection状態は通常時非表示

例:

    P1 PEKORA   ●○   HIT 3      85      HIT 2   ○○   MIKO P2
                                  ROUND 1

#### Comic effects

常時表示しない。

event時のみ:
- HIT!
- PARRY!
- JUST!
- DODGE!
- CLASH!

表示時間は短く、attack trajectoryを隠さない。

effect位置:
- 衝突点から少し外側
- character head / ahoge rootを覆わない
- timerを覆わない

#### Background

- background artは低contrast
- speed line / halftoneはevent時に一時追加
- Battle中の主役は常にアホ毛
- ステージ観客・看板等を置く場合も中央combat spaceを散らかさない

#### 5:4 / 16:9

現時点では5:4を確定しない。

C案での候補:
- 16:9全面を一つの漫画pageとして使用
- 中央combat spaceだけ約5:4の視覚的な主コマとして構成
- 左右余白には常設情報を詰めず、impact effect / subtle stage artに使う

#101で実画面mockup比較後に最終採否する。

### 10.4 UI-11 Match Result

#### Purpose

勝敗を一瞬で理解し、次の行動を迷わず選べること。

#### Layout

    ┌──────────────────────────────────────────────┐
    │                                              │
    │            YOU WIN / YOU LOSE / DRAW         │
    │           large comic impact title           │
    │                                              │
    │        character / score summary panel       │
    │                                              │
    │            primary next action               │
    │        secondary / tertiary actions          │
    │                                              │
    └──────────────────────────────────────────────┘

#### Result impact

- WIN / LOSE / DRAWは画面最大級のdisplay type
- 勝者側accent colorを部分使用
- backgroundに1回だけimpact line
- 連続flashは禁止
- 0.3〜0.5秒で通常Result layoutへ落ち着く

#### Ranked actions

既存機能契約を維持しつつcopyは#101で最終確定する。

候補:
- NEXT MATCH
- CHANGE CHARACTER
- TOP MENU

Rating変動はscore summary内へ整理し、buttonより上に表示する。

#### Friend Host actions

- 再戦する
- キャラクターを選び直す
- ルームを終了

「再戦する」をPrimary、「キャラクターを選び直す」をSecondary、「ルームを終了」をDestructiveとする。

#### Friend Guest

- ホストの選択を待っています…
- ルームを抜ける

Hostの選択待ちはspeech balloonではなくstatus captionとして明確にする。

#### Transition

- result enter: impact 250〜400ms
- button操作可能になる前に長いLoading専用画面を挟まない
- network同期中は同じResult画面上でstatus表示
- Host選択後はcomic panel wipeで次状態へ

## 11. #100 残Human Decision（解決済み履歴）

visual directionは確定済み。

以下は#100当時の未決項目であり、すべて §12〜§13 で解決済み。現在の仕様判断には §12〜§13 を使用する。

1. UI主言語
   - 英語short label + 日本語補足
   - 日本語中心
2. Paper基調の明るさ
   - warm light
   - neutral light
3. component角度
   - strong angular
   - moderate angular
4. motion強度
   - moderate
   - strong

#100でcommon component mockupと合わせて確定済み。


## 12. Design System v1

C: MANGA BOUT / COMIC IMPACTをGodotへ実装できる粒度まで数値化する。

### 12.1 Language / Copy

UIの主言語は**日本語中心**とする。

- 製品名・短い演出語・対戦イベントは英語を許可する
- 通常操作buttonは日本語を第一候補とする
- technical error / RPC名 / stack traceはユーザーへ直接表示しない
- buttonは「名詞」より「次に起きる動作」が分かる表現を優先する
- 破壊的操作は曖昧語を避ける

基本例:

| 意味 | 採用候補 |
| --- | --- |
| battle entry | 対戦する |
| ranked | ランクマッチ |
| friend | フレンド対戦 |
| confirm | 決定 |
| back | 戻る |
| cancel | キャンセル |
| rematch | 再戦する |
| change character | キャラクターを選び直す |
| leave room | ルームを抜ける |
| close room | ルームを終了 |
| settings apply | 適用 |
| defaults | 初期設定に戻す |

短いimpact textは英語を使用してよい。

- HIT!
- PARRY!
- JUST!
- DODGE!
- CLASH!
- WIN!
- LOSE
- DRAW

### 12.2 Color Tokens

| Token | Hex | Purpose |
| --- | --- | --- |
| paper_0 | #FFF8E8 | page / light surface |
| paper_1 | #F3E9D4 | secondary surface |
| paper_2 | #DED2BA | disabled surface |
| ink_0 | #151515 | primary ink |
| ink_1 | #2A2A2A | raised dark surface |
| ink_2 | #4A4A4A | secondary text on light |
| impact_yellow | #FFD43B | primary action / highlight |
| p1_blue | #3F86FF | player 1 |
| p2_red | #FF4F58 | player 2 |
| danger | #D73535 | destructive |
| success | #2D9B59 | success |
| info | #2E73D2 | info / reconnect |
| white | #FFFFFF | reverse text |

Contrast rule:
- body textは背景とのWCAG AA相当を目安にする
- Impact Yellow上の文字はInk固定
- P1/P2色だけで状態を伝えず、label / iconを併用する

### 12.3 Typography Scale

フォントファイルは別途選定するが、roleとsizeを先に固定する。

1280x720基準:

| Role | Size | Weight | Usage |
| --- | ---: | --- | --- |
| display_xl | 64 | 800-900 | WIN / LOSE / major impact |
| display_l | 40 | 800 | screen title |
| heading_l | 28 | 700 | section title |
| heading_m | 22 | 700 | card / panel title |
| body_l | 18 | 500 | main body |
| body_m | 16 | 500 | labels |
| caption | 13 | 500 | secondary info |
| number_xl | 72 | 800-900 | Battle timer |
| number_l | 28 | 700 | Hit / Rating |

1600x900以上では1.125〜1.25倍まで拡大可能。1920x1080で2倍にはしない。

### 12.4 Spacing / Layout Tokens

基準unitは8px。

| Token | px |
| --- | ---: |
| xs | 4 |
| s | 8 |
| m | 16 |
| l | 24 |
| xl | 32 |
| 2xl | 48 |
| 3xl | 64 |

- safe margin: 32px
- wide screen max content width: 1440px
- modal max width: 720px
- primary column width: 320〜420px
- minimum interactive height: 44px
- standard button height: 52px
- primary button height: 60px

### 12.5 Shape / Border

- radius 0〜6pxを基本とし、大きなpillは使用しない
- cut-corner: 8〜16px
- border: 2px standard / 4px impact
- offset shadow: 4px 4px 0 Ink
- selected state: 4px Impact Yellow frame + Ink outline
- focus ring: 3px P1 BlueまたはImpact Yellow
- panel tiltは最大1.5deg相当まで。読みやすさを崩す角度は禁止

### 12.6 Button Variants

#### Primary

- Impact Yellow fill
- Ink border 3px
- Ink text
- standard height 60px
- hover: y -2px / offset shadow +2px
- pressed: y +2px / shadow縮小
- disabled: paper_2 + ink_2

#### Secondary

- paper_0 fill
- Ink border 2px
- Ink text
- hover: paper_1

#### Destructive

- danger fill
- white text
- Ink border 2px
- 使用対象: room終了 / 明確な破壊操作
- Guest自身の「ルームを抜ける」はSecondary寄りでよく、room全体終了と視覚区別する

#### Back

- small Secondary
- 左下またはheader左
- 画面によって位置を変えない

### 12.7 Form Components

#### Dropdown

- height 48px
- Ink border 2px
- selected rowはImpact Yellow
- arrow iconはInk
- disabledはpaper_2

#### Slider

- track 6px
- knob 18px
- active fill Inkまたはaccent
- valueは右側へ数値表示

#### Toggle

- 48x26px
- ON: Impact Yellow + Ink knob
- OFF: paper_2 + Ink
- label textでもON/OFFを併記する

#### Text Input

- height 52px
- uppercase code入力はletter spacingを広めにする
- invalidはDanger border + 1行error
- technical messageを表示しない

### 12.8 Manga Panel

共通panel component。

- Paper fill
- Ink border 3px
- optional cut-corner
- optional halftone background
- title captionを上端へ重ねられる
- decorative line / burstはcontent layerと分離する

Panel variants:
- standard
- selected
- impact
- dark
- error

### 12.9 State Feedback

#### Loading

- full-screen blockingは必要時だけ
- 既存画面を維持できる場合はinline statusを優先
- animationはアホ毛がしなる2〜3frame風loop
- copy例: 「読み込み中…」

#### Waiting

- user actionが不要なら状態と理由を明示
- copy例: 「対戦相手を探しています…」
- Cancel可能なら同じ画面にCancelを残す

#### Error

- title: 「接続できませんでした」
- body: 人間が取れる次actionだけ書く
- Retry / Top Menu等を明示
- stack trace / RPC名 / source line禁止

#### Reconnect

- Battle画面を可能な限り維持
- status stripで「再接続中…」
- countdownがある場合だけ秒数表示
- reconnect成功時は短い「復帰しました」feedback

### 12.10 Transition

| Transition | Duration | Usage |
| --- | ---: | --- |
| hover | 100ms | component |
| press | 80ms | component |
| menu panel in/out | 200ms | menu |
| comic wipe | 220ms | screen |
| character card change | 160ms | character select |
| result impact | 360ms | result |
| status toast | 180ms | status |

easing:
- UI normal: ease-out
- impact: back/overshootを弱く
- Battle中に長いtransitionを入れない

### 12.11 Battle Specific Tokens

- top HUD height: 88〜104px
- timer hitbox-free safe zone: center top 160px幅
- timer size: 64〜72px
- head-top visible height: battle content高の20〜30%
- eye lineより上だけを表示
- impact text max width: battle areaの24%
- impact text表示: 180〜300ms
- screen shake: 2〜4px / 80〜140ms / major event限定

### 12.12 Responsive Breakpoints

- 1280x720: minimum reference
- 1600x900: standard
- 1920x1080: standard large

Rules:
- UIを単純scale-upしない
- max content widthを設ける
- hero art / manga backgroundはcropする
- body text sizeは極端に増やさない
- Battle combat spaceを最優先で確保する
- Fullscreen / Windowでnavigation位置を変えない

## 13. #100 Design System確定

C案採用画像をHuman Reviewで「いいデザイン」と確認済み。

以下をv1 design systemとして採用し、#101へ渡す。

- visual direction: C MANGA BOUT / COMIC IMPACT
- language: 日本語中心 + impact textのみ英語
- base: warm Paper + Ink
- shape: moderate angular / comic panel
- motion: moderate、impact eventだけstrong
- color tokens: §12.2
- typography roles: §12.3
- spacing / component tokens: §12.4〜12.8
- feedback / transition: §12.9〜12.10
- Battle composition: 頭頂部 + アホ毛のみ


## 14. UI-01〜UI-12 最終Screen Design v1

本節は #101 の正本とする。機能contractは `SCREEN_DESIGN.md` / `DETAILED_DESIGN.md` を維持し、見た目・copy・interaction・transitionを本節で確定する。

### 14.1 UI-01 Top Menu

Purpose:
- ゲームの入口
- 3秒以内に「アホ毛で戦う対戦ゲーム」と理解できる
- 最も強いactionは対戦開始

Final copy:
- 対戦する
- ランキング
- 設定
- ゲームを終了

Layout:
- 左: menu caption panels
- 右: 大きなhero manga panel
- 上: AHOGE LEGEND logo
- 下: version / fan-game notice等のsecondary information

Primary:
- 対戦する

Transition:
- 選択方向へcomic wipe 220ms

### 14.2 UI-02 Settings

Purpose:
- 端末設定を安全に変更・保存する

Final sections:
- オーディオ
- 画面
- 操作

Final copy:
- マスター音量
- BGM音量
- SE音量
- ボイス音量
- 表示モード
- 解像度
- VSync
- 初期設定に戻す
- 適用
- 戻る

Interaction:
- Window時のみResolution有効
- Fullscreen時Resolution disabled
- DEFAULTは未適用
- APPLYでruntime反映 + local保存
- BACKで未APPLY変更破棄

Visual:
- 漫画誌面の設定表
- 装飾は少なめ
- section captionをInk帯で統一

### 14.3 UI-03 Battle Mode Select

Purpose:
- Ranked / Friendの違いを一目で理解して選ぶ

Final copy:
- ランクマッチ
- フレンド対戦
- 戻る

Supporting copy:
- ランクマッチ: 「レートが変動するオンライン対戦」
- フレンド対戦: 「ルームコードで友だちと対戦」

Layout:
- 2枚の大型manga panelを左右または上下に配置
- Ranked: trophy / rating motif
- Friend: room code / two-player motif

Primary action:
- hovered card全体をclick targetにする

### 14.4 UI-04 Character Select

Purpose:
- アホ毛の見た目と戦闘特性を比較してキャラクターを選ぶ
- 選択単位はキャラクター固定セット（頭部 + 髪型 + 固有アホ毛）であり、頭部とアホ毛を別々に付け替えるUIは作らない
- アホ毛タイプ / 攻撃タイプは選択中キャラクターの属性表示であり、独立した装備選択ではない

Final copy:
- キャラクターを選ぶ
- 戻る
- 決定
- アホ毛タイプ
- 攻撃タイプ

Card:
- 頭頂部 + アホ毛cropを主役にする
- character name
- Ahoge Type
- Attack Type
- selectedはPaper fillを維持し、Impact Yellow 4px frameで示す。selected card全体をYellow fillにはしない
- 正式素材未導入の段階でも、各cardはcharacterごとのAhoge Typeが見分けられる専用vector previewを表示する
- Top Menu用の2人hero artをCharacter Selectのcard / selected previewへ流用しない

Selected detail:
- キャラクター名
- CharacterDefinitionの1行特徴
- アホ毛タイプ
- 攻撃タイプ
- 選択中characterだけを描く動くAhoge preview
- previewはvisual-onlyで、gameplay判定やserver stateの正本にしない

Transition:
- card change 160ms
- DECIDEでselected panel zoom → next

### 14.5 UI-05 Ranked Matching

Purpose:
- 対戦相手を探していること、待機を続けてよいこと、キャンセル可能なことを明確にする

Final copy:
- 対戦相手を探しています…
- 検索範囲を広げています…
- キャンセル

Layout:
- center manga panel
- ahoge line art 2本が互いを探すloop
- elapsed / technical rangeは通常ユーザーへ出さない

State:
- searching
- match found
- connecting
- error

Match found:
- 「対戦相手が見つかりました」
- 0.5〜1.0秒程度の短いimpact transitionでPreBattleへ

### 14.6 UI-06 Friend Match Menu

Purpose:
- room作成 / room参加を迷わず選ぶ

Final copy:
- ルームを作る
- ルームに参加
- 戻る

Layout:
- 2枚の大panel
- create: code ticket motif
- join: input / arrow motif

No technical wording.

### 14.7 UI-07 Friend Room Join

Purpose:
- 6文字room codeを入力して参加する

Final copy:
- ルームコードを入力
- 参加
- 戻る

Input:
- uppercase
- 6文字
- letter spacing大
- 入力枠は漫画caption
- pasteを許可

Error examples:
- 「ルームが見つかりません」
- 「このルームには参加できません」
- 「ルームは満員です」

RPC / source line / stack trace禁止。

### 14.8 UI-08 Friend Room Lobby

Purpose:
- Host / Guest / Character / Readyを一目で把握
- 次のactionを迷わない

Layout:
- 左: Host panel
- 右: Guest panel
- 中央上: room code
- 中央下: primary action
- room codeはCOPY可能

Final labels:
- ホスト
- ゲスト
- 待機中…
- キャラクター未選択
- 準備OK
- 準備中
- キャラクターを選ぶ
- 準備OKにする
- 準備を取り消す
- ルームを抜ける

Host close:
- destructive wordingは「ルームを終了」

Guest absent:
- Guest panelを空席ticketとして表示
- 「参加を待っています…」

### 14.9 UI-09 PreBattle Dialogue

Purpose:
- Battle前にキャラクターらしさを短く見せ、テンポを壊さない

Composition:
- 左右に頭頂部 + アホ毛 + 必要に応じて顔の一部を含む会話用portraitは許可
- Battle本編の「顔を出さない」制約はUI-10固有
- 2〜3コマ程度
- 1character 1〜2行
- voiceなし

Visual:
- speech balloon
- VS impact
- panel cut transition

Duration:
- manual skip可能
- auto進行する場合は全体2〜4秒程度を目安
-長文は禁止

### 14.10 UI-10 Battle / HUD

Non-negotiable:
- 顔・目・鼻・口・全身を表示しない
- 頭頂部 + 髪 + アホ毛 + 必要最小限の髪飾りのみ
- crop lineは目より上

HUD:
- center: 85 timer / ROUND
- left: P1 name / round / hit
- right: P2 name / round / hit
- normal connection indicatorは非表示
- reconnect時だけstatus strip

Final labels:
- ROUND 1 / 2 / 3
- HIT
- 再接続中…
- 相手を待っています…

Round Result:
- scoreboard上のplayer識別は P1 / P2 を使用する
- local client視点の一時event / Round Resultでは YOU / OPPONENT を使用する
- Drawは DRAW と表示する
- Round Result本文は `ROUND N / YOU|OPPONENT|DRAW / score` の順で表示する
- Result表示中は次RoundのWaiting / Countdownを重ねない

Event impact:
- HIT!
- PARRY!
- JUST!
- DODGE!
- CLASH!

Rules:
- 180〜300ms
- 実装基準は240ms。新しいeventが来た場合は前eventの消去timerを無効化して新eventの240msを開始する
- event textは時間経過後に自動消去し、次eventまで残留させない
- timer / attack trajectoryを覆わない
- root/head-topを覆わない

Battle field:
- 16:9全面をpageとして使う
- central combat spaceを視覚的な主コマとして確保
- 5:4固定はしない
- head-top visible height 20〜30%を初期基準
- wide余白へ常設情報を詰めない

### 14.11 UI-11 Match Result

Purpose:
- 結果を即理解
- 次のactionを迷わず選ぶ
- network syncでLoading専用画面へ戻さない

Impact:
- WIN!
- LOSE
- DRAW

Ranked copy:
- 次のランクマッチ
- キャラクターを変える
- トップへ戻る

Rating:
- Player Ratingは「プレイヤーレート  1500 → 1518  (+18)」形式
- Ahoge Ratingは「アホ毛レート  1500 → 1518  (+18)」形式
- 同キャラ戦ではAhoge Ratingの後ろへ「/ 同キャラ戦」を付与してよい
- Draw時もserver確定before / after / deltaを表示
- settlement取得失敗時は各欄を「プレイヤーレートを確認できませんでした」「アホ毛レートを確認できませんでした」とする

Friend Result common:
- 「フレンド対戦 / レート変動なし」を表示する
- Player Rating / Ahoge Ratingの変動行は表示しない

Friend Host copy:
- 再戦する
- キャラクターを選び直す
- ルームを終了

Friend Guest:
- 「ホストの選択を待っています…」
- 「ルームを抜ける」
- 再起動からFriend Resultへ復帰する場合も、初回表示前にHost / Guest roleを復元し、誤ったroleの操作を一瞬でも表示しない

Hierarchy:
1. Result
2. score / rating
3. primary action
4. secondary
5. destructive

### 14.12 UI-12 Ranking

Purpose:
- PLAYERとAHOGE LEGENDを明確に切替
- 自分 / 推しキャラの位置をすぐ確認

Final tabs:
- プレイヤー
- アホ毛レジェンド

Common:
- シーズン
- 順位
- 名前
- レート
- 戻る

PLAYER:
- player rank
- player name
- Rating / rank tier

AHOGE LEGEND:
- character rank
- character name
- Ahoge Rating
- 1位は「伝説のアホ毛」special badge

Layout:
- 左: ranking list
- 右: selected / top ahoge manga panel
- row heightは読みやすさ優先
- top 3だけ色 / badgeで強調
- 4位以下は静かなlist

Season:
- current / pastを明確に分ける
- 非公開時間帯は理由を人間語で表示

### 14.13 Common Loading / Waiting / Error / Reconnect

Loading:
- 「読み込み中…」
- ahoge loop
- 既存画面を維持できる場合はinline優先

Waiting:
- 何を待っているかを明示
- Cancel可能なら常に表示

Error:
- user action可能な表現だけ
- Retry / Back / Top Menu
- technical details禁止

Reconnect:
- Battle画面を維持
- strip: 「再接続中…」
- Round境界deadlineがある場合だけ秒数を出す

### 14.14 Navigation Rule

Back:
- header左または左下で統一
- destructiveではない

Decide:
- 右下 / center-bottomのPrimary

Cancel:
- 現在処理の中断
- Backと意味を混ぜない

Leave:
- Guest自身退出はSecondary
- room全体終了はDestructive

Top:
- 「トップへ戻る」
- 「終了」と混同しない

### 14.15 Responsive Rule

1280x720:
- minimum target
- button / body textを縮小しない
- artをcropする

1600x900:
- reference standard

1920x1080:
- whitespace増加
- content width max 1440
- componentを単純1.5倍にしない

Fullscreen:
- layout hierarchy維持

Window:
- same navigation positions

### 14.16 #101 Design Status

| ID | Screen | Status |
| --- | --- | --- |
| UI-01 | Top Menu | DESIGN v1 |
| UI-02 | Settings | DESIGN v1 |
| UI-03 | Battle Mode Select | DESIGN v1 |
| UI-04 | Character Select | DESIGN v1 |
| UI-05 | Ranked Matching | DESIGN v1 |
| UI-06 | Friend Match Menu | DESIGN v1 |
| UI-07 | Friend Room Join | DESIGN v1 |
| UI-08 | Friend Room Lobby | DESIGN v1 |
| UI-09 | PreBattle Dialogue | DESIGN v1 |
| UI-10 | Battle / HUD | DESIGN v1 |
| UI-11 | Match Result | DESIGN v1 |
| UI-12 | Ranking | DESIGN v1 |

Godot実装時にpixel-level調整は行うが、information hierarchy / copy / interaction / visual directionを無断変更しない。


## 15. 画像アセット主体UI実装

2026-10-02 Human Verificationで、code draw中心の第一モックは製品版として質感不足と判断した。

以後の最終UIは **画像アセット主体** とする。

- 背景 / button surface / panel / frame / decorationは画像
- fixed logo / fixed copy / 漫画効果音 / WIN・LOSE・DRAWは画像化可能
- timer数字は0〜9の個別画像
- player name / Rating / room code / 設定値 / 可変台詞等はtext
- 吹き出しは画像 + 可変text
- codeはlayout / state / animation / texture切替を担当する
- 本番用の漫画装飾を `draw_line` / `draw_rect` だけで完成扱いにしない

asset naming / file list / Godot node mappingの正本は `docs/UI_ASSET_SPEC.md` とする。

### 15.1 UI-01 Top Menu migration

UI-01は画像asset移行の最初の対象とする。

- full-screen background: TextureRect
- **background本体と集中線は別画像**
- halftone / corner decorationもbackgroundへ焼き込まず独立layer
- menu / hero frame: NinePatchRectまたはTextureRect
- button: TextureButton
- fixed button label: TextureRect
- logo / fixed catch copy: TextureRect
- hero artとhero frameも別画像
- debug-only controlsは製品visual hierarchyから分離

Top Menuでasset pipelineをHuman Verificationした後、Battle HUD / Result / 残り画面へ展開する。

### 15.2 Timer

Battle timerはLabelによる数字描画を最終仕様としない。

- 0〜9のPNGを使用
- integer secondsを桁へ分解してTextureRectで並べる
- zero paddingなし
- 85 → ... → 10 → 9 → ... → 0


## 16. コンセプト画像をvisual正本とする

2026-10-02 Human Reviewで、UI Design Proposal Board「C. MANGA BOUT」を最終UIのvisual referenceとして再確認した。

以後のasset制作では、単に「漫画風」「黄色・ピンク・黒」を使うだけでは不十分とし、**このconcept boardの具体的な画面構成・形状・情報密度・色の使い方へ合わせる**。

### 16.1 Top Menu

Top Menuはconcept boardの01 Top Menuを基準とする。

- 全体baseは黒〜濃紺のpanel / bar
- 選択中primary actionだけYellowで強く出す
- 非選択buttonは黒〜濃紺 / low contrast
- buttonは横長で細め、斜めcut / rough ink edgeを持つ
- pinkは主にaccent / slash / player identityへ限定し、button surfaceの常用色にしない
- glossy UI / rounded card / neon pink主体のbuttonは採用しない
- menu buttonを大きなpop-art stickerとして独立させない
- background / speed lines / character art / menu UIを重ねて1画面を構成する
- logo / title treatmentもconcept boardの白brush + red accent系を優先する

### 16.2 Battle / Result

- Battle HUDはconcept board 05の細い上部bar構成を基準とする
- timerは中央で最大視認性
- player sideはBlue / Redのaccent
- 漫画effectは大きく出すが、UI chromeそのものはdark baseで抑える
- Resultはconcept board 06のsplit manga panelを基準とする
- WIN / LOSEはillustrated impact assetとして扱う

### 16.3 Asset review rule

新規assetは次を満たさなければ不採用。

1. concept boardと並べて見て同一visual familyに見える
2. 色・形・線幅・情報密度がconcept boardと整合する
3. 単体で派手でも、画面へ置いた時にconcept boardから逸脱するものは不採用
4. Human Review前に「漫画風だからOK」と自己判断しない


### 16.4 Top Menu interaction / background correction

2026-10-03 Human Verificationで次を確定した。

#### Focus / Hover
- keyboard / controller focusとmouse hoverを別々のselected状態として同時表示しない
- mouseがmenu buttonへ入った時点で、そのbuttonへfocusも移す
- selected visualは常に1buttonだけ
- mouseが離れても最後に選択したbuttonのfocusを維持してよい

#### Background
- 現在のstadium background + speed linesはBattle向けvisualとして扱う
- UI-01 Top Menuではspeed linesを使用しない
- UI-01には専用background assetを使用する
- Top Menu backgroundはBattleより静かにし、menu / logoの可読性を優先する

#### Button micro animation
- focus / hover: 80〜120msで右へ8〜12px slide
- unfocus: 80〜120msで元位置へ戻る
- pressed: 40〜80msの押し込み + 1〜3px程度の短い振動
- animationはvisual-onlyでnavigation signalやhit areaを変えない
- 同時に複数buttonを動かさない


### 16.5 Top Menu tooltip

- Top Menuではtooltipを表示しない
- hover / focus時のfeedbackは色変化 + 微小slideだけで成立させる
- mouse hoverで説明ポップアップを重ねない
- menu項目の意味はlabel画像そのものから理解できることを前提とする


### 16.6 Battle character image prototype

UI-10のcharacter表示は、prototype checkpointとして頭部画像とアホ毛画像を分離する。

- 頭部: character固有のhead asset
- アホ毛: 同じCharacterDefinitionへ固定された別asset
- アホ毛はrootを頭部へ固定し、tipほど大きく曲がる
- idleでも停止させず、Live2Dのsecondary motionのように緩く連続変形する
- HeadMotion / action stateへ追従して遅れ・反動を加える
- visual-onlyでserver authoritativeなContact判定を変更しない
