# 固定アホ毛メッシュ実装・検証記録

関連: #102 / PR #105 / `AHOGE_MESH_DEFORMATION_DESIGN.md`
更新日: 2026-10-04

## 設計の適用差分

承認済み `AHOGE_MESH_DEFORMATION_DESIGN.md` の実装段階へ移行した。同書冒頭の「今回の成果は設計のみ」は設計commit `dec3658` 時点の記録であり、現在の実装状態は本書を参照する。

`BASIC_DESIGN.md` §10.2および `DETAILED_DESIGN.md` の「13.3 2D Head / Prototype-compatible Ahoge Motion」について、既存の全体角度・reach・頭部運動の計算式は維持し、描画部分へ次の変更を適用する。

- 「画像そのものだけを使用」「rotation / scaleだけを更新」という旧描画制限を、固定三角メッシュによるStraighten形状補間で拡張する。
- 元PNGのC字輪郭を保持するのはStraighten=0の待機・溜め形状。攻撃展開時は中央から実際の先端まで折り返しをほどく。
- 全体angle / reachは引き続き既存MotionRootが担当する。形状キーには追加の長さ倍率を入れず、既存reachとの二重伸長を避ける。
- 対応素材にだけメッシュを適用し、未対応・不一致時は従来Spriteを残す。表示失敗を無表示のまま通さない。
- 頭部画像・UIは2Dのまま。専用Battle直行起動、3D化、装備変更機能を追加しない。
- Contact / Hit / Defense / Round / Match / Rating、両者切断無効試合、片側再接続の規則を変更しない。

## 素材と固定メッシュ

対象: `assets/characters/prototype/charactor_01/ahoge.png`

- PNG寸法: 1254 × 1254
- PNG SHA-256: `bc0503b4ff52ce224201a58df4050eef386ab3bc1b3d34f3ec712fc26ea7c31c`
- Git blob SHA: `a88e4ddec49ba65d79460f952ae3a3b841e8203a`
- メッシュの根元接続点: `(558, 1146)`
- 毛先の閉じ点: `(1050, 544)`
- 85断面、幅方向5頂点、根元と先端の単独閉じ点: 427頂点
- 固定三角形: 680面
- 形状キー: Straighten=0から1まで0.125刻みの9形状

旧HTML素材のanchor `(180,1175)` を現行メッシュへ流用しない。現行PNGに合わせた断面と接続点を `.tres` に保持する。元画像自体は変更していない。

画像のY方向の走査で別の毛束部分を結ばず、根元からC字の折り返しを通って本当の先端へ向かう断面順序を固定した。待機頂点は元PNG座標そのもの、UVは0..1、隣接面は頂点IDを共有する。

形状は読み込み時に一度だけ生成する。中心線の各区間長を維持し、弧長の先頭10%を固定、10〜32%を移行区間として、後段の向きを最終的に-0.85 radへ揃える。断面内の元頂点位置は接線変化に合わせて回転する。実行時は隣接キーの同じ頂点だけを線形補間する。

## 実装ファイル

- `src/ui/ahoge_mesh_profile.gd`: 素材照合、固定断面、固定UV/index、9形状の生成と補間。
- `assets/characters/prototype/charactor_01/ahoge_mesh_profile.tres`: 現行LONG素材固有の断面座標・根元・毛先・識別情報。
- `src/ui/ahoge_mesh_deformer.gd`: MeshInstance2D / ArrayMesh。固定UV/indexを維持し、XYZ頂点領域だけを更新。全キーを含む描画境界を保持。
- `src/ui/ahoge_mesh_motion.gd`: 接触時刻までの直線化と中断・非表示時の復帰。
- `src/ui/ahoge_prototype_rig.gd`: 元の全体運動を残し、その内側へメッシュを接続。素材不一致時のSpriteを維持。
- `src/ui/fighter_visual.gd`: 頭部回転後の接続点と設定上のcontact_ratioを渡す。

## 時間制御

Straightenはばねで遅れるreachの値ではなく、既存のSTRIKE経過時間と設定上のcontact_ratioから求める。STRIKE進行率0.04からcontact_ratioまでのsmoothstepで0から1へ移行する。

COOLDOWN、PARRY、DODGE、STAGGERへの中断では遷移時の変形量から0.16秒で戻す。非表示・ROUND_LOCKED時は0へ戻し、非表示後の同一STRIKE再表示で過去の攻撃変形を再発させない。TipHookは導入しない。

## 実施した検証

製品接続検証対象: `8c0640d72b5d1e211b3614624f36ed6b66aa359f`

`Ahoge mesh verification` #15は、Xvfb上のGodot 4.7.2、Compatibility / llvmpipeによる実描画で成功した。headlessでNode存在だけを確認した試験ではない。

- 実際のGodot出力で427頂点・680三角形・9キーを照合。
- 全8補間区間について符号付き面積の2次式の端点と内部極値を検査。最小2倍面積は6.76747で正、局所反転・退化なし。
- 辺の共有回数と外周を照合し、意図しない内部境界なし。
- 大域的な外周自己交差を257サンプルで別検査。連続全区間の大域的非交差の数学的証明とは扱わない。
- 元Spriteと変形量0の実描画を同じ座標・scale・filterで比較。alpha欠け比率は約0.0228%、premultiplied色差指標は約0.00008461。
- 17段階の実描画が非空。頂点更新によって絵が変形し、0へ戻すと元の絵へ戻る。
- 最終キーの先端側中心線の目標方向誤差は約0.00044度。
- 製品FighterVisualで、通常STRIKE 0.20秒と最大チャージSTRIKE 0.13秒を、30/60/120fps、左右配置の12条件で検証。いずれも接触時刻のStraighten=1、Cooldown後=0。
- PARRY中断、非表示からの再表示、ROUND_LOCKEDを検証。
- 頭部回転後の接続点とメッシュ根元の最大誤差は約0.000137px。

実行コマンド:

```bash
./scripts/godot-import.sh
xvfb-run -a godot --path . --rendering-method gl_compatibility --audio-driver Dummy --script res://tests/ahoge_mesh_render_test.gd
python tools/ahoge_mesh/verify_geometry_and_render.py
xvfb-run -a godot --path . --rendering-method gl_compatibility --audio-driver Dummy --script res://tests/ahoge_mesh_cycle_test.gd
```

CI artifactにはtested_commit.txt、元Sprite比較画像、17段階の形状画像、通常・最大チャージの接触フレームと攻撃連続フレーム、geometry.json、report.json、cycles.jsonを保存する。

## 確認の境界と残るHuman Verification

今回の自動試験は形状補間とその製品描画への接続を検証する。全体角度・reachの到達軌道、対戦相手との見た目上の接触、最終的な太さ・ハイライトの好ましさまで合格と断定しない。

とくに非等方reach拡縮後の幅は姿勢によって変わるため、数学的に完全不変とは扱わない。最大倍率での見た目、通常GameFlowでの操作感は人間さんの実機確認対象。Mac / Windowsの実機rendererおよびexport済み配布物での素材照合も未検証。

Human Verification未実施。PR #105はマージせず、通常GameFlowから実機で確認する。
