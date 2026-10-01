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
