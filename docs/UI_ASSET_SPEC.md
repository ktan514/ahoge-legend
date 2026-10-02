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

### 5.2 Background decoration

```text
assets/ui/top_menu/decor_halftone.png
assets/ui/top_menu/decor_speed_lines.png
assets/ui/top_menu/decor_corner_marks.png
```

- 透過PNG
- 個別layerとして配置
- responsive時にcrop / reposition可能とする

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

### 5.9 Product Top Menu composition

```text
bg_top_menu
├─ decor_halftone
├─ decor_speed_lines
├─ logo_ahoge_legend
├─ frame_menu
│  ├─ TextureButton(primary) + label_battle
│  ├─ TextureButton(secondary) + label_ranking
│  ├─ TextureButton(secondary) + label_settings
│  └─ TextureButton(secondary) + label_exit
├─ frame_hero
│  └─ art_top_menu_hero
├─ copy_kicker
├─ copy_main
└─ copy_tagline
```

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
