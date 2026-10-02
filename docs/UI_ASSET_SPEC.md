# AHOGE LEGEND UI画像アセット仕様 v1

## 1. 目的

AHOGE LEGENDの最終UIは、コード描画だけで見た目を構成せず、画像アセットを主役にする。

役割を次のように分離する。

- 画像アセット: 背景、枠、ボタン、装飾、固定見出し、漫画効果音、数字などの視覚表現
- コード: 画面遷移、状態管理、Texture差し替え、可変値、表示タイミング
- テキスト: プレイヤー名、Rating、room code、設定値、可変台詞など

UI/UXの正本は `docs/UI_UX_DESIGN.md` とし、本書は画像アセットの実装仕様を定義する。

## 2. 基本ルール

### 2.1 画像形式

- PNG
- sRGB
- 透過が必要な素材はalpha付き
- reference layoutは1600x900
- 元データは必要に応じて高解像度で制作してよい
- repositoryへ組み込むruntime assetはPNGとする

### 2.2 Godot component

| 用途 | Godot node |
| --- | --- |
| 全画面背景 | TextureRect |
| 固定画像 / logo / copy | TextureRect |
| 伸縮するpanel / frame | NinePatchRect |
| 操作button | TextureButton |
| button内の固定文字画像 | TextureRect |
| 可変文字 | Label |
| 数字画像 | TextureRectを桁数分並べる専用component |
| 漫画効果音 | TextureRect / Control |
| 吹き出し | NinePatchRect + Label |

buttonの文字を画像化する場合も、buttonの状態画像とlabel画像は分離する。
これにより同じbutton baseを他画面でも再利用する。

### 2.3 TextureButton state

原則として次の4状態を持つ。

- normal
- hover
- pressed
- disabled

selectedを持つUIは別途selected textureを持つ。

### 2.4 画像とテキストの境界

画像:
- button surface
- panel / frame
- background
- decorative line / halftone / speed line
- logo
- 固定見出し
- 固定の漫画効果音
- WIN / LOSE / DRAW等の強い固定演出
- timerの0〜9

テキスト:
- player name
- room code
- Rating数値
- Ranking数値
- 設定値
- error詳細
- 可変の説明文
- 可変台詞

hybrid:
- 吹き出し本体は画像、本文はLabel
- Rating panelは画像、before / after / deltaはLabel
- Ranking rowは画像、順位 / 名前 / 数値はLabel

## 3. Directory

```text
assets/ui/
├─ common/
├─ logo/
├─ top_menu/
├─ character_select/
├─ battle/
├─ result/
├─ ranking/
├─ settings/
├─ digits/
├─ effects/
└─ balloons/
```

## 4. Common button assets

### 4.1 Primary

表示基準サイズ: 420x100

```text
assets/ui/common/btn_primary_normal.png
assets/ui/common/btn_primary_hover.png
assets/ui/common/btn_primary_pressed.png
assets/ui/common/btn_primary_disabled.png
```

### 4.2 Secondary

表示基準サイズ: 420x100

```text
assets/ui/common/btn_secondary_normal.png
assets/ui/common/btn_secondary_hover.png
assets/ui/common/btn_secondary_pressed.png
assets/ui/common/btn_secondary_disabled.png
```

### 4.3 Destructive

表示基準サイズ: 420x100

```text
assets/ui/common/btn_destructive_normal.png
assets/ui/common/btn_destructive_hover.png
assets/ui/common/btn_destructive_pressed.png
assets/ui/common/btn_destructive_disabled.png
```

### 4.4 Back / small action

表示基準サイズ: 240x72

```text
assets/ui/common/btn_small_normal.png
assets/ui/common/btn_small_hover.png
assets/ui/common/btn_small_pressed.png
assets/ui/common/btn_small_disabled.png
```

button画像は文字を含めない。
固定文字を画像化する場合はlabel画像を上に重ねる。

## 5. UI-01 Top Menu asset list

### 5.1 Background

```text
assets/ui/top_menu/bg_top_menu.png
```

- full-screen base
- reference 1600x900
- Paper texture / manga page感を含める
- layout上重要な文字やbutton位置は焼き込まない
- **集中線を焼き込まない**
- halftone / corner decorationも原則として焼き込まない
- 背景本体は「単独で表示しても成立する静かなbase」にする
- 装飾強度は上位layerで調整する

### 5.2 Background decoration

```text
assets/ui/top_menu/decor_halftone.png
assets/ui/top_menu/decor_speed_lines.png
assets/ui/top_menu/decor_corner_marks.png
```

- すべて透過PNG
- **背景本体とは完全に別file**
- 個別layerとして配置
- responsive時にcrop / reposition可能とする
- `decor_speed_lines.png` は集中線だけを持ち、背景色・Paper texture・文字・frameを含めない
- `decor_halftone.png` はhalftoneだけを持つ
- `decor_corner_marks.png` は角装飾だけを持つ
- 装飾同士も1枚へ合成せず、個別にON/OFF可能とする

### 5.3 Logo

```text
assets/ui/logo/logo_ahoge_legend.png
```

- 現在のLabelタイトルは最終実装で置換
- logoは固定画像
- 背景透過

### 5.4 Menu panel

```text
assets/ui/top_menu/frame_menu.png
```

- NinePatchRect
- reference表示サイズ: 約480x590
- 漫画コマ / ink frame / paper textureを含む
- debug-only controlはこの製品panelへ混ぜない

### 5.5 Hero frame

```text
assets/ui/top_menu/frame_hero.png
```

- NinePatchRectまたは固定TextureRect
- reference表示サイズ: 約900x590
- hero art自体とは別file
- comic panelとして強い輪郭を持たせる

### 5.6 Hero art

```text
assets/ui/top_menu/art_top_menu_hero.png
```

- Top Menu専用key visual
- Character Select用previewへ流用しない
- 正式キャラ素材決定前は仮画像で差し替え可能
- 現在のcode描画による青赤2頭部heroは本番assetではない

### 5.7 Main fixed copy

```text
assets/ui/top_menu/copy_main.png
assets/ui/top_menu/copy_kicker.png
assets/ui/top_menu/copy_tagline.png
```

初期候補:
- copy_main: 「小さなアホ毛で、でっかく熱く。」
- copy_kicker: 「アホ毛でつながる、熱い対戦。」
- copy_tagline: 「PLAY WITH YOUR AHOGE.」

これらは固定演出文なので画像化する。
将来copyを変更する場合は画像assetを差し替える。

### 5.8 Menu label images

```text
assets/ui/top_menu/label_battle.png
assets/ui/top_menu/label_ranking.png
assets/ui/top_menu/label_settings.png
assets/ui/top_menu/label_exit.png
```

表示内容:
- 対戦する
- ランキング
- 設定
- ゲームを終了

各labelは透明背景。
TextureButtonのchild TextureRectとして中央へ重ねる。

### 5.9 Product Top Menu layer composition

Top Menuの描画順を次で固定する。

```text
Z0  bg_top_menu
Z1  decor_halftone
Z2  decor_speed_lines
Z3  decor_corner_marks
Z4  frame_menu
Z5  button surfaces
Z6  button label images
Z7  frame_hero
Z8  art_top_menu_hero
Z9  logo_ahoge_legend
Z10 copy_kicker
Z11 copy_main
Z12 copy_tagline
Z13 optional foreground accent
```

重要:
- `bg_top_menu.png` と `decor_speed_lines.png` は同一画像へ統合しない
- `frame_hero.png` と `art_top_menu_hero.png` も統合しない
- button surfaceとbutton labelも統合しない
- logo / fixed copyも背景へ焼き込まない
- 各layerはGodot側で個別に位置・scale・visibleを制御可能にする

### 5.10 Top Menu complete asset manifest

```text
assets/ui/top_menu/
├─ bg_top_menu.png
├─ decor_halftone.png
├─ decor_speed_lines.png
├─ decor_corner_marks.png
├─ frame_menu.png
├─ frame_hero.png
├─ art_top_menu_hero.png
├─ copy_main.png
├─ copy_kicker.png
├─ copy_tagline.png
├─ label_battle.png
├─ label_ranking.png
├─ label_settings.png
└─ label_exit.png

assets/ui/logo/
└─ logo_ahoge_legend.png

assets/ui/common/
├─ btn_primary_normal.png
├─ btn_primary_hover.png
├─ btn_primary_pressed.png
├─ btn_primary_disabled.png
├─ btn_secondary_normal.png
├─ btn_secondary_hover.png
├─ btn_secondary_pressed.png
├─ btn_secondary_disabled.png
├─ btn_destructive_normal.png
├─ btn_destructive_hover.png
├─ btn_destructive_pressed.png
├─ btn_destructive_disabled.png
├─ btn_small_normal.png
├─ btn_small_hover.png
├─ btn_small_pressed.png
└─ btn_small_disabled.png
```

このmanifestに含まれないvisual要素をTop Menu最終版へ追加する場合は、先に本書へfileを追加してから実装する。

### 5.11 Reference size and responsibility

| Asset | Reference size | Stretch | 内容 |
| --- | ---: | --- | --- |
| bg_top_menu.png | 1600x900 | cover | base backgroundのみ |
| decor_halftone.png | 1600x900 | cover/crop | halftoneのみ |
| decor_speed_lines.png | 1600x900 | cover/crop | 集中線のみ |
| decor_corner_marks.png | 1600x900 | cover/crop | corner accentのみ |
| frame_menu.png | 480x590基準 | NinePatch | menu frameのみ |
| frame_hero.png | 900x590基準 | NinePatch/固定 | hero frameのみ |
| art_top_menu_hero.png | hero area基準 | contain/crop | hero artのみ |
| logo_ahoge_legend.png | content依存 | contain | logoのみ |
| copy_*.png | content依存 | contain | fixed copyのみ |
| label_*.png | button内 | contain | fixed button labelのみ |

### 5.12 Layer independence rule

次を禁止する。

- 背景へ集中線を焼き込む
- 背景へlogoを焼き込む
- 背景へ固定copyを焼き込む
- hero artへframeを焼き込む
- button surfaceへ文字を焼き込む
- halftoneと集中線を同じPNGへ統合する

理由:
- responsive調整
- intensity調整
- animation
- state差し替え
- asset reuse
- Human Verificationでの個別修正

を可能にするため。

## 6. Debug UI

`LOCAL TEST BATTLE` 等の開発専用controlは製品画像アセットの対象外とする。

- debug buildでは表示可能
- Product Top Menuのvisual hierarchyへ混ぜない
- Human Verificationで最終Top Menuを見る場合、debug領域が製品デザイン評価を邪魔しない配置または非表示手段を用意する

## 7. Timer digit assets

Battle timerはLabelではなく0〜9の画像で構成する。

```text
assets/ui/digits/digit_0.png
assets/ui/digits/digit_1.png
assets/ui/digits/digit_2.png
assets/ui/digits/digit_3.png
assets/ui/digits/digit_4.png
assets/ui/digits/digit_5.png
assets/ui/digits/digit_6.png
assets/ui/digits/digit_7.png
assets/ui/digits/digit_8.png
assets/ui/digits/digit_9.png
```

表示基準:
- 1桁: 約72x96
- 2桁: 2枚を横並び
- zero paddingなし
- 85 → 84 → ... → 10 → 9 → ... → 0
- `:` は使用しない

専用component `DigitNumberDisplay` へ整数を渡し、桁ごとのTextureRectを組み立てる。

## 8. Battle effect image policy

固定の演出文字は画像化する。

```text
assets/ui/effects/fx_hit.png
assets/ui/effects/fx_parry.png
assets/ui/effects/fx_just.png
assets/ui/effects/fx_dodge.png
assets/ui/effects/fx_clash.png
assets/ui/effects/fx_stagger.png
assets/ui/effects/fx_overtime.png

assets/ui/effects/sfx_doka.png
assets/ui/effects/sfx_bashi.png
assets/ui/effects/sfx_gakiin.png
```

- `HIT!` 等をLabelで最終描画しない
- 「ドカッ」「バシッ」等は文字そのものをillustration assetとして制作する
- codeは表示位置、scale、rotation、240ms前後のlife timeを制御する

## 9. Balloon policy

```text
assets/ui/balloons/balloon_left.png
assets/ui/balloons/balloon_right.png
assets/ui/balloons/balloon_center.png
```

- balloon本体: NinePatchRect
- 可変台詞: Label
- tail向きでleft / rightを切り替える
- 台詞そのものを画像へ焼き込まない

## 10. Completion condition for asset migration

Top Menuのasset移行は次を満たしたとき完了とする。

- [ ] 背景がTexture asset
- [ ] menu frameがTexture / NinePatch asset
- [ ] hero frameがTexture asset
- [ ] Top Menu buttonがTextureButton
- [ ] 固定button labelが画像
- [ ] logoが画像
- [ ] 固定catch copyが画像
- [ ] code drawによる本番装飾を使用しない
- [ ] 1280x720 / 1600x900 / 1920x1080で破綻しない
- [ ] hover / pressed / disabledを目視確認
- [ ] Human Verification PASS

## 11. 制作順

1. common button state 4種 x primary / secondary
2. Top Menu background
3. menu frame
4. hero frame
5. logo
6. fixed button label 4種
7. fixed copy 3種
8. Top Menu hero art
9. Godot TextureButton / NinePatch実装
10. Human Verification
11. timer digit 0〜9
12. Battle effect文字
13. balloon
14. Result assets


## 12. Top Menu最小実装セット

最初のHuman Verificationでは、完成版asset一式を先に揃えず、次の**最小セット**だけを制作・実装する。

### 12.1 必須asset

```text
assets/ui/top_menu/
├─ bg_top_menu.png
├─ decor_speed_lines.png
├─ logo_ahoge_legend.png
├─ btn_menu_normal.png
├─ btn_menu_hover.png
├─ btn_menu_pressed.png
├─ btn_menu_disabled.png
├─ label_battle.png
├─ label_ranking.png
├─ label_settings.png
└─ label_exit.png
```

合計: 11ファイル。

### 12.2 この段階では作らないもの

次は初回asset migrationの必須対象外とする。

- hero frame
- hero art
- menu frame
- halftone overlay
- corner decoration
- fixed catch copy画像
- destructive専用button texture
- small button texture
- debug専用asset

まず「背景 / 集中線 / logo / button / fixed label」の5要素だけでTop Menuを再構成する。

### 12.3 button共通化

初回Top MenuではBattle / Ranking / Settings / Exitごとにbutton本体画像を作らない。

共通の4stateを使う。

```text
btn_menu_normal.png
btn_menu_hover.png
btn_menu_pressed.png
btn_menu_disabled.png
```

button文字だけを差し替える。

```text
label_battle.png
label_ranking.png
label_settings.png
label_exit.png
```

これにより最初のasset制作量を抑えつつ、画像主体UIの品質と操作感をHuman Verificationできる。

### 12.4 背景と集中線の責務

`bg_top_menu.png`:
- 背景本体だけ
- 集中線なし
- logoなし
- buttonなし
- fixed copyなし
- UI frameなし

`decor_speed_lines.png`:
- 透明背景
- 集中線だけ
- 背景色なし
- logoなし
- halftoneなし
- 他decorなし

### 12.5 初回Godot構成

```text
TopMenu
├─ TextureRect      bg_top_menu
├─ TextureRect      decor_speed_lines
├─ TextureRect      logo_ahoge_legend
└─ VBoxContainer
   ├─ TextureButton + label_battle
   ├─ TextureButton + label_ranking
   ├─ TextureButton + label_settings
   └─ TextureButton + label_exit
```

この構成でHuman Verificationを行い、visual directionが承認された後にframe / hero art / additional decorationを追加する。
