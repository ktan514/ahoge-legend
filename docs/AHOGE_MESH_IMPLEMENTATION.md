# 固定アホ毛メッシュ実装・検証記録

関連: #102 / PR #105 / PR #106 / `AHOGE_MESH_DEFORMATION_DESIGN.md`

## 仕様の具体化

現行LONG素材を監査して、旧HTMLの茶色素材とは異なるピンク素材用の断面を制作した。旧 `(180,1175)` ではなく、現行画像内の根元接続点は `(558,1124)` を初期基準とする。頭部側の接点は別データ `head_attachment_reference=(0.525,0.085)` として保持し、頭部transformを適用する。

- 原本寸法: 1254 x 1254。
- 原本SHA-256: `bc0503b4ff52ce224201a58df4050eef386ab3bc1b3d34f3ec712fc26ea7c31c`。
- 毛束に沿う73断面。根元と真の毛先には小さい追加区間を置く。
- 215頂点 / 284三角形。両端は重複頂点を作らず一点のfanで閉じる。
- 各通常断面は左輪郭・内部・右輪郭の3頂点を共有し、元画像の座標をUVへ対応させる。
- `Straighten=0 / 0.25 / 0.5 / 0.75 / 1` の5キー。
- 根元側を固定し、元の区間長を変えずに曲率をほどく。Reachの倍率をキーへ二重適用しない。
- 最大直線化時は毛先側をlocal 0度（前方）へそろえる。追加TipHookは使わない。

## 焼き出しと実行時の境界

`.tres` に素材識別・制作済み中心線・左右断面距離・距離パラメータを保存する。`AhogeMeshProfile.prepare()` は読み込み後一度だけ、固定UV/index、待機頂点、5形状キーと表示範囲を焼き出して保持する。この初期化は再入時に配列を増やさない。実行時にalpha解析・輪郭抽出・再triangulation・曲線からのmesh再構築は行わない。

実行時は焼き出した隣接キー間で頂点位置だけを線形補間する。`AhogeMeshDeformer` は一つのArrayMesh surfaceを維持し、RenderingServerから取得したstrideとPackedVector3Arrayのbyte数を照合した上で頂点領域だけを更新する。UV/index/RIDは更新しない。

Editorでは原本SHA-256、原本PNGが含まれないexportでは正規化RGBAのSHA-256を使用する。import時の透明縁のRGB補正による誤判定を避けるため、alphaが20/255未満のRGBのみ0へ正規化する。寸法・画素が異なる素材へ古いmeshを使用しない。

## 検証

`python tools/ahoge_mesh/inspect_source.py` は原本・輪郭・SHA-256を保存する。`Ahoge mesh verification` はheadless幾何学検査に加え、XvfbとOpenGLで実際に描画しSpriteとのalpha比較、途中形状、表示された先端・根元、固定UV/index/RIDを検査する。画像は7日間CI artifactへ保存する。PRのmerge treeだけでなく、作業ブランチのpushでもexact HEADの検査を行う。

補間区間の各三角形の符号付き面積を2次式で評価し、両端だけでなく内部極値を検査する。Pythonの独立検査は面の共有辺・単一閉境界も確認する。非隣接境界の交差は、動く端点の方向判定が0になる時刻（2次式の根）と区間中点で検査する。同一直線上を動く辺では端点の座標が一致する時刻も含める。浮動小数点許容差は原画像座標で1e-5とし、離散サンプルのみの確認と区別する。

## 並行変更の保護

`0beed52`からの作業中に元ブランチへ同名3ファイルの別実装が追加された。fast-forward失敗を確認後、上書きを行わず `feature/102-ahoge-straighten-render` / PR #106へ作業を分離した。元ブランチを巻き戻さない。統合時は両実装のAPI・制作データ・試験を照合する。

## 現在の到達点

- 現行素材に沿った固定メッシュと直線化キー、頂点更新deformerを追加。
- 幾何学・連続区間・OpenGL実描画・FighterVisualの実時間cycle試験を追加し、ローカルGodot 4.7.2で成功。exact HEAD CIは別途確認する。
- 既存全体運動クラスは変更せず、`AhogeMeshRig`で継承し形状パラメータだけ追加。FighterVisualは同リグを使用し、頭頂部接点へ実transformで接続する。
- Human Verification未実施。PRはマージしない。

## 最終調整と接続

初期のlocal -70度は実時間STRIKEでは上を向きすぎるため、最大直線化方向をlocal 0度へ変更した。根元から急に90度近く曲げず、中心線の7.5%〜40%で連続的に方向を変える。変更後も補間区間の最小面積比0.71069以上を確認した。形状キー自体に長さ倍率は追加していない。

`AhogeMeshRig` は元の `AhogePrototypeRig` を継承する。頭部運動とwhole angle/reach計算を再実装せず、同じ入力に対する値が元リグと一致することを毎フレーム検査する。STRIKEの開始から既存contact_ratio=0.70までにStraightenを現在値から1へ補間し、Cooldownは0.16秒、割込みは0.10秒で現在値から0へ戻す。非表示・Round lockでは形状を解除する。設定は表示専用でサーバー判定を変更しない。

Spriteとmeshは排他表示する。非有限パラメータ等でdeformerが失敗したら、同じ接点の元Spriteへ戻し警告を記録する。この状態はmesh_ready=falseでありメッシュ成功扱いにはしない。頭部回転・左右反転・パリィ中の接点はHeadSpriteの実transformで計算する。

## 確認範囲

- 215頂点・284三角形・5キー。面積の連続区間1136件、非隣接境界の連続区間40608件に反転・交差なし。
- OpenGL/llvmpipe実描画: 待機Spriteとのalpha差0.001648%。全キーと中間値、UV/index/RID不変、描画された先端・根元を確認。
- 30/60/120fps、左右配置、通常0.20秒・最大チャージ0.13秒でSTRIKEを終了させる12cycleを検証。短い攻撃時間を延長して合格させない。
- パリィ割込み、再構成、Round lock、異常時Sprite fallbackを検証。
- 対戦相手の頭部への見た目上の到達距離とMac上の操作感はHuman Verificationで確認する。現在の試験はその合格を意味しない。
- #105への統合は並行変更との照合が必要。#106を勝手にマージしない。
