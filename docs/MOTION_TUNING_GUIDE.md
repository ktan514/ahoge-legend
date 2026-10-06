# ロングの動きを自分で調整する

対象: `feature/102-manga-ui-implementation` / PR #105。
関数名・定数名で検索して調整箇所を特定する。ロング型は頭部の前後速度・回転速度を入力とする動的柔軟追従を導入済みで、根元を頭部へ固定したまま中間〜毛先だけが遅れて追従する。数値は自動検証済みの初期値だが、見た目の最終合格はMac Human Verificationで決める。

## 1. まずプレビューを開く

ゲームを開く代わりに、リポジトリのルートで実行する。

```bash
godot --path . res://tools/motion_preview/MotionPreview.tscn
```

Godot importが必要なfresh checkoutでは、先に `./scripts/godot-import.sh` を実行する。
これはGodotの開発専用Scene。Nakama/Docker/P2/マッチングは不要で、通常のAppRootや対戦参加処理は起動しない。既存BattleHUDの実メッシュを、本体のActionMotionとContactDirectorで動かす。動作式を別言語へ複製したプレビューではない。

画面の使い方:

| 操作 | 使い方 |
| --- | --- |
| 動作 | 通常攻撃、チャージ攻撃、溜め保持、パリィ、攻撃からパリィへの中断 |
| チャージ量 | チャージ攻撃/中断で使用。通常攻撃は0、溜め保持は最大まで保持 |
| アホ毛柔らかさ | 0.0で動的chainなし、1.0で最大。NeckRangePreviewと同じ設定 |
| LONG側/相手 | 左右反転と、相手LONG/SHORTを確認 |
| 再生/停止 | Spaceでも切替可能。キー入力欄の編集中はショートカットを使わない |
| 1コマ戻る/進む | 選択した計算fpsの1コマ。30fps=1/30秒、60fps=1/60秒、120fps=1/120秒 |
| 速度 | 0.1/0.25/0.5/1倍。演出の観察速度のみで、製品の攻撃時間を変更しない |
| 時間スライダー | 任意の時点で停止。逆送りは先頭から計算し直す |
| 接触時刻へ | 現行CombatConfigの接触予定時刻へ移動。パリィ単独等では無効 |
| 中心線・軌跡 | 青が現在の毛束中心線、緑が毛先の軌跡、赤い輪が接触目標 |
| 三角メッシュ | 実描画頂点の三角形を表示。面の潰れ・ねじれの観察用 |
| 全長 | 全体変換を適用した後の、画面上の中心線長。縮小復帰の観察に使用 |
| 画面保護 | `1.000`は保護縮小なし。1未満なら領域内へ収める縮小が発生中 |
| コード再読込 | 保存済みコードの構文を確認後、同じGodotでツールを再起動。constを確実に読み直す |
| PNG保存 | `artifacts/motion-preview/`へプレビューの1枚を保存 |

HUD内の85秒やHIT数はこのツールでは勝敗を計算していない。実通信、Hit通知、Just Parry成否は確認しない。最後の確認は従来の通常GameFlowで行う。

## 2. 調整するコードの地図

```text
BattleHUD
  → BattleContactDirector.advance(delta)
      → BattleFighterVisual._process(delta)   頭部と動作時計
          → AhogeActionMotion                毛束の形
              → AhogeParryMotion             パリィの先端変形
      → BattleFighterVisual.present_toward()  相手位置・全体回転・伸長・振り抜き
          → AhogeMeshDeformer.set_action_pose()  固定メッシュへ描画
```

最初に編集するファイルは次の3つ。

| ファイル | 編集する目的 |
| --- | --- |
| `src/ui/ahoge_action_motion.gd` | チャージの垂れ、曲がりの伝播、振り抜き中の形、C字への復帰 |
| `src/ui/battle_fighter_visual.gd` | 実際の接触位置、全体の向き・伸長、下へ抜ける目標位置、全体縮尺の復帰 |
| `src/ui/ahoge_parry_motion.gd` | 先端側の払い幅、動く範囲、払うタイミング |

`ahoge_prototype_rig.gd`には旧whole-angle/reach式が残っているが、現在のBattleの最終形状・変換は上記の処理で設定される。そこだけを変更しても意図したBattleの調整にならない。`ahoge_mesh_profile.gd`/`.tres`のUV・indexや`ahoge_mesh_deformer.gd`の描画バッファを最初に変更する必要はない。

## 3. チャージで後ろへ垂らす

`ahoge_action_motion.gd`冒頭:

```gdscript
const HANG_UP_ANGLE: float = -1.30
const HANG_TURN: float = 3.0
```

`configure()`が最大溜めの区間角度を作る。

```gdscript
var hang_angle: float = HANG_UP_ANGLE - HANG_TURN * smoothstep(0.30, 0.90, s)
hang_angles.append(lerpf(angle, hang_angle, smoothstep(0.08, 0.22, s)))
```

`s`は画像の高さではなく、毛束に沿った弧長の割合。0が根元、1が毛先。
`HANG_UP_ANGLE`は後方アーチの基準角、`HANG_TURN`は末端へ進むほど加える曲がり量。単位はrad。符号と曲がりが組み合わさるため、値を増やせば必ず下がるとは限らない。

`hanging_angle()`は待機→最大溜めの途中形を制御する。`transfer = 2.0 * sin(PI * p) * ...` は途中だけ出る曲げ、`p`は溜め進行。最大溜めがよくても途中が巻き込む場合は、この関数をコマ送りで確認する。

最初は `HANG_TURN` を0.1ずつ変更し、溜め保持で元の値と比較する。根元、輪郭、頭へのめり込み、画面保護倍率も見る。良い見た目を保証する設定例ではない。

## 4. ムチのように曲がりを伝える

`ahoge_action_motion.gd`:

| 場所 | 現在値/式 | 主な効果 |
| --- | --- | --- |
| `TRAVEL_BEND` | `0.60` | 接触前に移動する曲げの強さ |
| `traveling_bend()` | `center = 0.18 + 0.95 * q` | 曲げの帯の位置。qはSTRIKE開始0→接触1 |
| 同関数の分母 | `0.24` | 曲げ帯の広さ。小さくすると局所的、大きくすると広いしなり |
| `release_at()` | `smoothstep(0.02 + 0.35*s, 0.42 + 0.58*s, q)` | 根元側から先端側へ解放する時間差 |
| `FOLLOW_WAVE_BEND` | `1.10` | 接触後に伝わる曲げの強さ |
| `FOLLOW_END_BEND` | `0.78` | 振り抜き終端側の曲げの強さ |
| `follow_bend()` | 移動する帯＋末端の下向き曲げ | 叩いた後の中間部と先端の形 |

例えば比較実験として `TRAVEL_BEND` を `0.60→0.70` と1個だけ変える。0.25倍で根元→中央→毛先の順に形が移るかを見てから、1倍で確認する。
`release_at()`の終端を無造作に遅らせると接触時刻に先端がほどけなくなる。q=1までに到達する条件を保持し、接触確認も実行する。

これらはSTRIKE固有の基準形状を作る係数であり、動的な慣性追従とは別層。頭部運動に対する遅れは後述の柔軟追従定数で調整し、`TRAVEL_BEND`だけを大きくして柔らかさを代用しない。

## 5. 下まで振り抜く／縮んで戻る箇所

まず、形状と目標位置を分ける。

```gdscript
# src/ui/battle_fighter_visual.gd
const FOLLOW_THROUGH_PX: Vector2 = Vector2(42.0, 100.0)
const FOLLOW_EDGE_MARGIN: float = 12.0

# src/ui/ahoge_action_motion.gd
const FOLLOW_SECONDS: float = 0.16
const RECOVER_SECONDS: float = 0.24
```

`FOLLOW_THROUGH_PX.x`は接触後の前進量、`.y`は下方向の目標移動量。画面座標はYが正で下。
`FOLLOW_SECONDS`は接触後の通過に使う秒数。例えば `0.16→0.22` は長く振り抜く比較実験になるが、同じ距離なら速度は下がる。より強い勢いになる保証ではない。

`_follow_end_for()`は目標をBattle下端内側12pxへ制限する。`100→140`としても、既に下端制限に到達していれば見た目はほぼ変わらない。単にクリップを無効化して画面外へ捨てない。

`follow_progress()`は現在 `u * (2.0 - u)`。接触直後から進み、最下点へ近づくほど減速する。

**縮んで戻る動作の修正は、RECOVER_SECONDSだけでは不十分。**

- `AhogeActionMotion._compute_pose()`のCOOLDOWN: 区間角度をrestへ戻す。
- 同箇所の `0.18 + 0.06 * fractions[i]`: 根元から毛先までの復帰時間差。
- `BattleFighterVisual.present_toward()`の `end_transform.interpolate_with(base, smoothstep(0.0, 0.20, action_motion.recovery_seconds()))`: 全体の回転・伸長を中立へ戻す。

最後の`0.20`を伸ばすと全体縮尺の戻りを遅くできるが、縮尺復帰自体は残る。区間角度の復帰と全体縮尺の復帰がどの順番か、画面上の「全長」を見ながら調整する。接触後の長さを一定に保つ方式へ変える場合は、ここを設計変更する必要がある。

## 6. 曲がった毛先で大きくパリィする

`src/ui/ahoge_parry_motion.gd`:

```gdscript
const FIXED_FRACTION: float = 0.62
const FULL_FRACTION: float = 0.80
const PREPARE_ANGLE: float = 0.24
const SWEEP_ANGLE: float = -0.72
const RECOIL_ANGLE: float = 0.12
```

根元〜62%は局所変形なし。62〜80%で追加角度を増やし、80%より先はほぼ同じ追加角度を与えて湾曲した毛束を返す。

最初は`FIXED_FRACTION`を維持し、`SWEEP_ANGLE`だけ `-0.72→-0.82`などへ変えて比較する。絶対値を増やすと返す角度が増える。正負を反転すると払い方向が変わる。角度増加で面反転や頭部へのめり込みが出ることもあるので、メッシュ表示と左右を確認する。

`sweep_at()`の進行率 `0.12 / 0.52 / 0.76 / 1.0` は、準備終了／払い最大／反動／復帰完了。タイミングを変えるならif境界とsmoothstep境界をそろえる。PARRY有効時間やJust受付時間はこの関数では変更しない。

## 7. チャージ攻撃を速くする

見た目のスロー再生と、対戦の攻撃速度は別物。

| Godot `src/config/combat_config.gd` | Nakama `server/nakama/src/combat_config.ts` | 現在値 |
| --- | --- | --- |
| `normal_windup_seconds` | `normalWindupSeconds` | 0.18 |
| `normal_strike_seconds` | `normalStrikeSeconds` | 0.20 |
| `charged_release_windup_seconds` | `chargedReleaseWindupSeconds` | 0.08 |
| `charged_strike_seconds` | `chargedStrikeSeconds` | 0.13 |
| `attack_contact_ratio` | `attackContactRatio` | 0.70 |

設定計算では離してから接触まで`windup + strike*contact_ratio`。現状でも通常0.320秒、最大チャージ0.171秒。サーバーでは30Hzのtickへ切り上げるため、細かい秒数変更が同じtick数に丸められる場合がある。
オンラインの速度を変えるならGodotだけでなく、Nakama側の値、設計書、タイミング試験も同時に変更する。サーバー側のこれらは共通設定であり、LONG専用パラメータではない。他タイプを維持してLONGだけ変える場合はcharacter/attack別の時間設定を導入する設計が必要。

## 8. 頭の切り返しに対する柔らかさを調整する

まず首単独プレビューを使う。

```bash
godot --path . res://tools/motion_preview/NeckRangePreview.tscn
```

旧4秒往復は廃止した。「攻撃速度テスト」は後端-0.4Dで保持した後、約0.15秒で前端+0.4Dへ切り返す。

現在の柔軟追従は9 controlの連結chain。根元頂点の位置だけを頭部へ固定し、control 0の角度は7Hzの根元ヒンジとして遅れて追従する。controlは0/4/10/18/30/45/62/80/100%へ配置して根元側を密にし、頭部Canvas X加速度も根元ヒンジから入力する。これにより毛先だけでなく根元直後から曲げを発生させる。

主な初期値:

| 定数 | 現在値 | 主な効果 |
| --- | ---: | --- |
| `SOFT_CONTROL_COUNT` | 9 | 毛束を代表する動的control数。根元側へ密配置 |
| `SOFT_ROOT_HINGE_HZ` | 7.0 Hz | 根元直後の角度が頭へ追従する速さ |
| `SOFT_ROOT_HINGE_DAMPING` | 0.44 | 根元ヒンジの減衰 |
| `SOFT_ROOT_MAX_OFFSET` | 0.22 rad | 根元直後で許す動的角度差 |
| `SOFT_ROOT_BLEND_END` | 0.12 | 根元ヒンジの曲げを分散する弧長範囲 |
| `SOFT_MAX_OFFSET_STEP` | 0.055 rad | 隣接区間の動的offset差上限。根元の折れ・面反転を防ぐ |
| `SOFT_CHAIN_HZ` | 8.5 Hz | control間で運動を伝える速さ |
| `SOFT_ROOT_DAMPING` | 0.50 | 根元側controlの減衰 |
| `SOFT_TIP_DAMPING` | 0.18 | 毛先側の減衰。低いほど振り遅れ・反動が残る |
| `SOFT_SHAPE_RESTORE_RATIO` | 0.05 | ActionMotion基準形状へ直接戻す弱い復元 |
| `SOFT_TIP_SPRING_GAIN` | 1.75 | 毛先へ伝播を運ぶspring力 |
| `SOFT_FORWARD_ACCEL_DRIVE` | 0.000010 | 頭部Canvas X加速度をcontrol 1へ与えるdrive |
| `SOFT_DRIVE_LIMIT` | 0.70 rad | 加速度driveの上限 |
| `SOFT_MAX_OFFSET` | 0.70 rad | 動的追加角の上限 |

「アホ毛柔らかさ」0.0ではchainを基準形状へ同期し、動的offsetを描画しない。1.0ではchain出力を100%使用する。静止時の形を別物にするパラメータではない。

確認する順序:

1. 根元**位置**は頭部へ固定したまま外れない。
2. 根元直後の接線角度は頭部へ完全固定せず、目視できる遅れが出る。
3. 頭部が前へ切り返した直後、根元側から曲げが始まる。
3. 中央の反転が後から来る。
4. 毛先の反転が最後に来る。
5. 毛先の移動速度が中央より明確に上がる区間がある。
6. 頭部停止後も中央・毛先が少し動き、その後基準形状へ収束。
7. 実STRIKEでは接触2px、固定メッシュ、振り抜き契約を維持する。

調整順は、まず `SOFT_CHAIN_HZ` で伝播時間、次に `SOFT_TIP_SPRING_GAIN` で毛先の加速、最後に `SOFT_TIP_DAMPING` で反動量を合わせる。複数を同時に大きく変更しない。

## 9. 最小の反復手順

1. まずデフォルトでプレビューを開き、対象動作を0.25倍で再生する。
2. VS Code等で1つだけ値を変更して保存する。
3. 「コード再読込」で再起動し、同じ動作を再生する。
4. 良さそうなら1倍速、左右、相手LONG/SHORT、チャージ0/0.5/1、途中パリィを確認する。
5. 変更した値、狙い、確認結果を仕様へ記録する。まだ比較中なら「調整中・未採用」と記す。
6. 自動検査と最後の通常GameFlowを確認してからPRへ反映する。

仕様更新の対応先:
- 全体方針: `docs/AHOGE_WHIP_PROJECTION.md`
- 現行の曲げ・通過仕様: `docs/AHOGE_ROPE_REVISION.md`
- 新しい調整記録: 変更対象の定数/関数、旧値→新値、目的、未確認事項を上記へ追記

途中実験の値は自動テストの合格を保証しない。失敗したテストを値変更に合わせて無条件に緩めず、面の破綻・見切れ等の不具合か、仕様変更で期待値が古くなったかを切り分ける。

```bash
# 基本検査
godot --headless --path . --script res://tests/run_all.gd
# ロープの形状・通知回帰
godot --headless --path . --script res://tests/ahoge_mesh_rope_test.gd
# ツールの再現性・入力列検査
godot --headless --path . --script res://tests/motion_preview_test.gd -- --preview-test
```

表示の検査は画面ありで実行する。Linux CIのxvfbはMacでは不要。

```bash
godot --path . --script res://tests/ahoge_mesh_action_test.gd
godot --path . --script res://tests/ahoge_mesh_parry_test.gd
godot --path . --script res://tests/ahoge_mesh_followthrough_test.gd
```

## 10. 制限

ツールには頂点をドラッグするLive2D風GUIやパラメータを永久保存するスライダーはない。現在は本体コードの定数・関数を編集して再起動する方式。Godot Inspectorへconstは表示されない。
本体と同じ描画処理でも、ここでは入力時刻を直接与えており、実オンラインの状態更新・遅延・成功通知は再現していない。
別ツールで作ったモデルや見た目だけを正本に置き換えず、最終確認は同じコードの通常対戦で行う。
