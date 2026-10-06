# 承認済み直線素材と頭部・ロングモーション

関連: #102 / PR #105。

## 正本素材

2026-10-05にHuman承認された963×1633透過PNGを `ahoge_straight.png` として使用する。

- file SHA-256: `9055d9d420b6d81b8545a479e9eebeae995e06a6057d666be35fed01e62ca0a7`
- Git blob SHA: `d9125c8ef6a12a8000d5976d5691c5cb1944ce39`
- root anchor: `(476, 1596)`
- tip: `(622.5, 13)`
- LONG_TESTの正式prototype表示はこの素材を使用する。
- 旧 `ahoge.png` / `ahoge_mesh_profile.tres` は比較・回帰用に残す。

Mac Human VerificationとGitHub CIで別素材を使う状態を禁止する。Human Verification対象HEADではCharacterCatalog、Texture、Profileの3点が同じ承認素材を参照していることを確認する。

## 素材座標と待機姿勢

直線PNGの画素座標をそのままゲーム内の待機形にしない。

- `bind_vertices`: 直線PNG上の根元→毛先断面。UVの正本。
- `idle_pose_vertices`: ゲーム内の待機C字。形状・全長・断面幅の正本。
- `rest_vertices`: 実行時はidle poseを使用する。
- UV / index / mesh RIDは固定し、ActionMotionと柔軟chainでは頂点位置だけを更新する。
- 427頂点 / 680三角形 / 5列断面を維持する。

これにより、素材のハイライト・輪郭を直線PNGから取得しながら、待機・チャージ・攻撃では既存ゲーム空間の長さと幅を維持する。

## Profile選択

`AhogeMeshDeformer` はTextureごとにProfileを選択する。

- `ahoge_straight.png` → `ahoge_straight_profile.tres`
- 旧 `ahoge.png` → `ahoge_mesh_profile.tres`

TextureとProfileのpath・寸法・SHA-256が一致しない場合はmesh構築を拒否し、誤ったUV/Profileを適用しない。

## 頭部・柔軟chainとの関係

頭部位置・取り付け角度・根元固定は `BattleFighterVisual` を正とする。
ロングの二次動作は `AhogeActionMotion` の9 control連結chainを使う。

- 根元位置と取り付け角度は頭部へ同frame固定。
- CHARGING/WINDUPは既存後方アーチを正とし、chainは状態を更新する。
- STRIKE/COOLDOWNでは頭部の加速・減速をcontrol 1へ入力し、中央→毛先へ運動を伝える。
- PARRYは現段階では既存局所払いを維持する。
- server authoritativeの攻撃時間、接触、Hit、Defense、勝敗は変更しない。

## 検証

`tests/straight_head_motion_test.gd` で次を確認する。

- 承認PNGのfile digest一致。
- bind verticesとUV一致。
- bind形状とidle poseの分離。
- 427頂点、固定index、三角形非退化。
- 5動作×左右×2解像度。
- 頭部移動・回転と根元一致。
- 画面内包含。
- STRIKE接触誤差2px以下。

さらに既存のHead motion / Neck range / Ahoge mesh / Motion preview / Godot / Online foundationを併用する。
CI PASSだけでモーション品質合格とはせず、同一asset/profileを使うMac通常GameFlowでHuman Verificationする。
