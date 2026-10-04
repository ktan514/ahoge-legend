# 固定アホ毛メッシュ実装・検証記録

関連: #102 / PR #105 / `AHOGE_MESH_DEFORMATION_DESIGN.md`

## 仕様の具体化

現行LONG素材を監査して、旧HTMLの茶色素材とは異なるピンク素材用の断面を制作した。旧 `(180,1175)` ではなく、現行画像内の根元接続点は `(558,1124)` を初期基準とする。頭部側の接点は別データ `head_attachment_reference=(0.525,0.085)` として保持し、頭部transformを適用する。

- 原本寸法: 1254 x 1254。
- 原本SHA-256: `bc0503b4ff52ce224201a58df4050eef386ab3bc1b3d34f3ec712fc26ea7c31c`。
- 毛束に沿う73断面。根元と真の毛先には小さい追加区間を置く。
- 215頂点 / 284三角形。両端は重複頂点を作らず一点のfanで閉じる。
- 各通常断面は左輪郭・内部・右輪郭の3頂点を共有し、元画像の座標をUVへ対応させる。
- `Straighten=0 / 0.25 / 0.5 / 0.75 / 1` の5キー。
- 根元側を固定し、元の区間長を変えずに曲率をほどく。Reachの倍率をキーへ二重適用しない。
- 最大直線化時は毛先側をlocal -70度へそろえる。追加TipHookは使わない。

## 焼き出しと実行時の境界

`.tres` に素材識別・制作済み中心線・左右断面距離・距離パラメータを保存する。`AhogeMeshProfile.prepare()` は読み込み後一度だけ、固定UV/index、待機頂点、5形状キーと表示範囲を焼き出して保持する。この初期化は再入時に配列を増やさない。実行時にalpha解析・輪郭抽出・再triangulation・曲線からのmesh再構築は行わない。

実行時は焼き出した隣接キー間で頂点位置だけを線形補間する。`AhogeMeshDeformer` は一つのArrayMesh surfaceを維持し、RenderingServerから取得したstrideとPackedVector3Arrayのbyte数を照合した上で頂点領域だけを更新する。UV/index/RIDは更新しない。

Editorでは原本SHA-256、原本PNGが含まれないexportでは正規化RGBAのSHA-256を使用する。import時の透明縁のRGB補正による誤判定を避けるため、alphaが8/255未満のRGBのみ0へ正規化する。寸法・画素が異なる素材へ古いmeshを使用しない。

## 検証

`python tools/ahoge_mesh/inspect_source.py` は原本・輪郭・SHA-256を保存する。`Ahoge mesh verification` はheadless幾何学検査に加え、XvfbとOpenGLで実際に描画しSpriteとのalpha比較、途中形状、表示された先端・根元、固定UV/index/RIDを検査する。画像は7日間CI artifactへ保存する。

補間区間の各三角形の符号付き面積を2次式で評価し、両端だけでなく内部極値を検査する。非隣接境界の重なりは別検証とする。素材監査やNode存在だけで描画合格とはしない。

## 現在の到達点

- 現行素材に沿った固定メッシュと直線化キー、頂点更新deformerを追加。
- 幾何学・実描画試験を追加。実行結果を確認してから通常Battleへ接続する。
- 既存Sprite表示と全体運動のコードはまだ変更していない。
- Human Verification未実施。PRはマージしない。
