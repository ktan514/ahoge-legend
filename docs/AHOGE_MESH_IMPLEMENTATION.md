# 固定アホ毛メッシュ実装・検証記録

関連: #102 / PR #105 / `AHOGE_MESH_DEFORMATION_DESIGN.md`
更新日: 2026-10-04

## 現在状態：接触同期の追加修正

実機録画では毛先直線化自体は確認できたが、先端が相手へ到達しない時刻にHITが表示され、頭部後退時の見切れも残ったため、攻撃全体のHuman VerificationはNG。

追加設計は `AHOGE_CONTACT_PRESENTATION.md`。既存全体運動の計算を出発点として残すが、無補正で描画する制限を変更する。

追加したコード:
- `src/ui/battle_fighter_visual.gd`: Battle専用の頭部余白・実輪郭の接触点・実メッシュ先端を使う表示補正。頭部移動を制限した後の位置から速度・加速度を計算する。既存FighterVisualを継承する。
- `src/ui/battle_contact_director.gd`: 両頭部を更新してから左右の表示姿勢を確定する。各頭部・rigの更新は1frameに1回。確定Hit通知、重複・遅延イベントの抑止を担当する。
- `src/ui/battle_hud.gd`: 上記を製品Battleへ接続。頭部の最小高さを380pxにし、下部表示分の余白を確保。共通Battle領域のclipは最後の保護に限定する。
- `tests/battle_contact_presentation_test.gd`: 実BattleHUDで、2解像度・3fps・左右・通常/最大チャージ・相手LONG/SHORTの48条件を検査する試験を追加。実メッシュ先端の2px以内到達、相手近傍の描画差、画面内包含、Hit通知と中断・非表示を検査する。
- `.github/workflows/ahoge-mesh-tests.yml`: 接触表示試験を構文確認・実描画の順で実行し、証跡を保存する導線を追加。

形状キー・UV/index・元PNGは変更しない。server authoritative判定、両者切断無効試合、通常GameFlowは変更しない。

### 今回実行できた検証

`tools/ahoge_mesh/verify_contact_math.py` をPythonで実行した。前回Godot artifactのgeometry.jsonを入力に、表示補正式の31,212条件を検査しPASS。最大接触誤差約8.27e-13、幅方向の追加倍率誤差約4.44e-16、検査した補正行列の行列式はすべて正。

これは数式の数値検証であり、GDScriptの構文確認・Godotの実行・実描画のPASSではない。

```bash
python tools/ahoge_mesh/verify_contact_math.py artifacts/ahoge-mesh/geometry.json --output artifacts/ahoge-mesh/contact-math.json
```

### 検証停止

コードHEAD `185c0a2607347a6d4c015c8329ade579f0028c02` のGodot tests #504、Ahoge mesh verification #26、Online foundation #482はGitHub上でfailure。先行する同一作業のジョブ詳細もRunner ID=0、steps=[]で終了し、ログ取得はBlobNotFoundだった。テストが実行されて失敗した結果とは区別する。

Runnerが割り当てられない理由は取得できていない。課金・利用時間・権限等の原因を推定で断定せず、設定を変更しない。追加した48条件のGodot描画検査は未実施、コードの構文確認も未完了。新しい比較画像や成功件数を捏造しない。

CI復旧後に新しいHEADで全検査を実行し、証跡を確認してからMac実機Human Verificationへ提出する。PR #105は未マージを維持する。

## 初回メッシュ設計の適用差分

承認済み `AHOGE_MESH_DEFORMATION_DESIGN.md` の実装段階へ移行した。同書冒頭の「今回の成果は設計のみ」は設計commit `dec3658` 時点の記録である。

`BASIC_DESIGN.md` §10.2および `DETAILED_DESIGN.md` の「13.3 2D Head / Prototype-compatible Ahoge Motion」へ次の変更を適用した。

- 「画像そのものだけを使用」「rotation / scaleだけを更新」という旧描画制限を、固定三角メッシュによるStraighten形状補間で拡張。
- 元PNGのC字輪郭を保持するのはStraighten=0の待機・溜め形状。攻撃展開時は中央から実際の先端まで折り返しをほどく。
- 全体angle / reachは既存MotionRootが基準計算を担当。形状キーには追加の長さ倍率を入れない。現在の接触表示補正は本書冒頭と追加設計に従う。
- 対応素材にだけメッシュを適用し、未対応・不一致時は従来Spriteを残す。
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

## 基準の実装ファイル

- `src/ui/ahoge_mesh_profile.gd`: 素材照合、固定断面、固定UV/index、9形状の生成と補間。
- `assets/characters/prototype/charactor_01/ahoge_mesh_profile.tres`: 現行LONG素材固有の断面座標・根元・毛先・識別情報。
- `src/ui/ahoge_mesh_deformer.gd`: MeshInstance2D / ArrayMesh。固定UV/indexを維持し、XYZ頂点領域だけを更新。全キーを含む描画境界を保持。
- `src/ui/ahoge_mesh_motion.gd`: 接触時刻までの直線化と中断・非表示時の復帰。
- `src/ui/ahoge_prototype_rig.gd`: 元の全体運動を残し、その内側へメッシュを接続。素材不一致時のSpriteを維持。
- `src/ui/fighter_visual.gd`: 頭部回転後の接続点と設定上のcontact_ratioを渡す。

## 基準の時間制御

Straightenは既存のSTRIKE経過時間と設定上のcontact_ratioから求める。STRIKE進行率0.04からcontact_ratioまでのsmoothstepで0から1へ移行する。

COOLDOWN、PARRY、DODGE、STAGGERへの中断では遷移時の変形量から0.16秒で戻す。非表示・ROUND_LOCKED時は0へ戻し、非表示後の同一STRIKE再表示で過去の攻撃変形を再発させない。TipHookは導入しない。Battle専用の確定接触表示と復帰は追加設計に従う。

## 以前に実施した形状検証

製品接続検証対象: `8c0640d72b5d1e211b3614624f36ed6b66aa359f`

`Ahoge mesh verification` #15は、Xvfb上のGodot 4.7.2、Compatibility / llvmpipeによる実描画で成功した。

- 427頂点・680三角形・9キーを照合。
- 全8補間区間の符号付き面積の端点と内部極値を検査。最小2倍面積6.76747、局所反転・退化なし。
- 辺の共有回数と外周を照合し、意図しない内部境界なし。
- 外周自己交差を257サンプルで別検査。連続全区間の数学的証明とは扱わない。
- 元Spriteと変形量0の実描画を比較。alpha欠け比率約0.0228%、premultiplied色差約0.00008461。
- 17段階の実描画と元形状への復帰を確認。
- 最終キーの先端側中心線の目標方向誤差約0.00044度。
- 通常STRIKE 0.20秒、最大チャージ0.13秒、30/60/120fps、左右の12条件で接触予定時刻のStraighten=1、Cooldown後=0を確認。ただし相手への実接触を検査していなかった。
- PARRY中断、非表示からの再表示、ROUND_LOCKEDを検証。
- 頭部接続点とメッシュ根元の最大誤差約0.000137px。

```bash
./scripts/godot-import.sh
xvfb-run -a godot --path . --rendering-method gl_compatibility --audio-driver Dummy --script res://tests/ahoge_mesh_render_test.gd
python tools/ahoge_mesh/verify_geometry_and_render.py
xvfb-run -a godot --path . --rendering-method gl_compatibility --audio-driver Dummy --script res://tests/ahoge_mesh_cycle_test.gd
```

以前のCI成功は、今回の接触同期コード・実描画の成功を保証しない。Mac / Windows実機renderer、export済み配布物、追加修正のHuman Verificationは未検証。
