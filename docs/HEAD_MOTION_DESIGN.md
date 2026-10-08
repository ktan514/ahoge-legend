# 承認素材と頭部連動モーション

関連: #102 / PR #105。基準コード: `6b26be6f7bcb372142d911a540dea22a2bdcf80e`。

## 要求と作業範囲

人間さんは縦に伸びたピンクのアホ毛画像を承認した。画像の承認と、ゲームへの組み込み・モーション品質の合格は区別する。
続く要求は「攻撃、チャージ、パリィするときはアホ毛だけじゃなくて頭も動かす」。頭部の並進と傾きを独立した調整箇所へまとめ、既存BattleHUDと調整プレビューの両方で同じ実装を使用する。

2026-10-06に配布ZIPの承認PNGを再取得し、file SHA-256 `9055d9d420b6d81b8545a479e9eebeae995e06a6057d666be35fed01e62ca0a7` と963×1633寸法を確認した。LONG_TESTはこの素材と専用profileをGitHub正本へ統合し、Mac Human VerificationとCIが同じTexture/Profileを使う状態へ揃える。画像承認とモーション品質合格は引き続き別ゲートとする。

## 頭部の仕様

基本設計§10.1と詳細設計§2.2の、頭部の動きにアホ毛を連動させる原則を具体化する。従来のパリィの微小な頭部cueだけに限定せず、三動作で目視できる並進と傾きを用意する。ただし顔・全身は表示しない。

- チャージ: 頭部が後退して後方へ傾き、根元を引く。長押しで移動し続けず静止する。
- 攻撃: 現在の後退姿勢から頭部が先行して前方へ切り返す。接触より前に主な頭部駆動を終え、叩いた後の傾きと復帰を続ける。
- パリィ: 短い頭部の切り返しを追加する。アホ毛は頭部相対で湾曲を保つ近距離の末端払いであり、頭を動かすためにアホ毛全体を遠方まで伸ばさない。
- 中断: 状態変更時の実際の頭部位置・傾きを引き継ぐ。開始frameで新しい初期姿勢へ飛ばさない。
- 左右: 一つの前方基準の姿勢を位置X・傾きの符号で反転する。

## 初期調整値

`src/ui/battle_head_motion.gd`に集約する。Vector3のXは前方px、Yは下方px、Zは角度degree。見た目の初期値であってサーバー判定値ではない。

| キー | X | Y | 傾き |
| --- | ---: | ---: | ---: |
| CHARGE | -20 | 8 | -5 |
| WINDUP | -26 | 10 | -6 |
| STRIKE_DRIVE | 24 | -4 | 8 |
| STRIKE_FOLLOW | 20 | 6 | 10 |
| PARRY_PREPARE | -5 | 2 | -2 |
| PARRY_SWEEP | 12 | -3 | 6 |
| PARRY_RECOIL | 4 | 1 | 2 |

STRIKEの24%までに駆動姿勢へ移り、接触付近までは保持し、後半に振り抜き姿勢へつなぐ。駆動終端を`STRIKE_DRIVE_END=0.24`へ集約する。COOLDOWNは冒頭0.12秒まで傾きを保持し、0.24秒で戻す。PARRYの頭部切り返しは毛先の払いより前にピークを持たせる。防御有効時間・Just受付・攻撃接触・チャージによる時間差は変更しない。

## 描画の責務

- `BattleHeadMotion`: 状態と経過時間から、前方基準の位置と傾きを返す純粋な姿勢計算。開始時刻は直前姿勢そのものを返す。
- `BattleFighterVisual`: 状態変更時の頭部姿勢を保存する。頭部を先に更新し、回転後の頭頂部anchorへ同じframeでアホ毛根元を接続する。
- 頭部の回転後の画像外接範囲で横方向の移動を制限し、見切れ防止と下端cropを維持する。
- **アホ毛の取り付け基準角度は頭部の傾きへ追従する。** `AhogePrototypeRig` の基準回転を `HeadSprite` の回転と一致させ、その子である `AhogeMotionRoot` がムチのしなり・攻撃・チャージ・パリィの相対回転を担当する。頭部回転は「取り付け角度」、MotionRootの回転は「毛束自身の動き」として分離する。
- アホ毛の中立変換は当該frameの独立した基準から再構築し、接触補正のskewを持ち越さない。
- 頭部相対のパリィ固定範囲・幅・根元、接触時の誤差契約を維持する。
- SHORTの未対応画像／仮描画をLONGのメッシュへ置換しない。

## 駆動時間と全体回転の検証履歴

初版`5c08015`ではSTRIKEの40%まで頭部を切り返す設定だった。頭部24条件・接触48条件・パリィ48条件は通過したが、最大チャージ/1280幅/120fpsで最大前方速度の順序が中央0.0333秒、根元0.0417秒、毛先0.0583秒となり、既存の根元先行検査で不合格になった。
`1649bcd`の駆動終端24%では根元と中央のピークがともに0.025秒となった。頭部の傾きを全毛束へ即時適用する構成が、中央部まで頭部と同時に加速させている可能性を切り分ける。
このため、頭部の位置・回転によるroot anchorの移動は保ち、毛束全体への追加剛体回転を除去して再検証する。しきい値を下げたり、根元と中央の同時ピークを合格へ変更したりしない。結果は最新HEADで確認する。

## 頭頂アンカーと能動アホ毛制御

2026-10-06のHuman Verificationで、現在のアホ毛接点が頭頂左寄りにあり、意図した頭頂位置より左へずれていることを確認した。LONG_TESTは頭画像の自動中央探索だけに依存せず、CharacterDefinitionに明示的な頭頂X比率を持つ。

- LONG_TEST head anchor X ratio: **0.64**
- YはそのX列で最初に見つかるalpha>=0.5の頭部表面。
- 根元頂点Vector2.ZEROはこの頭頂アンカーへ毎frame固定する。
- SHORT/未指定キャラクターは従来の0.50をdefaultとする。

### アホ毛制御を3層へ分離

これまでの「頭部の動きに受動追従するだけ」では、頭の勢い以上の打撃速度を作れず、相手を狙う自由度も不足する。ロング型は次の3層を合成する。

1. **Head Drive**
   - マウス長押しチャージ、後退、前方切り返し。
   - 頭部速度・加速度をアホ毛へ入力する。
   - 現在のHeadMotionは維持する。

2. **Passive Flex**
   - 根元固定の柔軟chain。
   - 頭部運動に対する遅れ、しなり、反動を作る。
   - NeckRangePreviewで調整している層。

3. **Active Strike**
   - STRIKE中にアホ毛自身が相手頭部を狙う。
   - 現在の柔軟角度を初期値として、根元側は慣性を残し、中腹〜毛先ほど相手方向へ能動的に向く。
   - 区間長を弧長方向に増加させ、メッシュ自体を伸長する。
   - chargedほど最大伸長量と能動turnを増やす。
   - 接触直前の全体Transform投影は残差補正だけに縮小する。
- 接触確定後はActive Strikeのtargetも接触時Canvas座標へfreezeし、相手のその後の移動を追尾しない。振り抜きは固定接触点からFollowThrough終点へ進む。
- 接触frameの最終表示後に、実427頂点と実`AhogeMotionRoot` Transformを保存する。ただし保存した427頂点は接触開始位置の記録専用とし、COOLDOWN中の描画形状として再利用しない。
- `0 <= follow_seconds < FOLLOW_SECONDS`では、ActionMotionが生成する基準弧長のfollow形状を使う。Active Strikeで伸びた局所弧長はSTRIKE終了と同時に持ち越さず、STRIKE以外の弧長固定契約を維持する。
- 振り抜き開始時、保存した接触Transformを基準弧長follow形状へそのまま適用した状態を安全側の始点とする。基準弧長follow形状の毛先を接触点へ完全投影したTransformが画面外になる場合は、この安全側始点→完全投影Transformの補間率を二分探索し、427頂点が全てarena安全領域内に残る最大率を振り抜き開始Transformとする。
- 基準弧長follow形状はfollow時間に応じて変化するため、画面内に収まる開始Transformは各frameの現在形状に対して再解決する。過去frameのTransformを形状変更後へそのまま固定して見切れを起こすことは禁止する。
- 各frameでは現在形状に対する安全な開始TransformからFollowThrough終点へ投影し、希望Transformが画面外になる場合は進行率だけを二分探索で制限する。全体uniform縮小は行わない。
- 前frameで実際に表示した毛先Canvas Yを保持し、次frameの軌道探索ではそのY以上を最小進行位置とする。画面内Transformの再解決は許すが、follow形状の変化を理由に毛先を上方向へ戻さず、接触後の振り抜き区間でCanvas Yを単調非減少とする。
- さらにTransform適用後の実描画毛先座標を最終postconditionとして検査する。実毛先Yが前frame実毛先Yを下回った場合は、その前frame Yまでだけ毛先を再投影し、427頂点がarena内に残る場合に補正Transformを採用する。単調性判定は中間計算値ではなく最終`AhogeDeformMesh.global_transform * source_tip`を正とする。
- この画面内制約ではarena fitによるframeごとのuniform縮小を使わない。断面幅・根元固定・基準弧長を維持し、振り抜き中の`last_safety_scale`は1.0のままとする。
- `follow_seconds == FOLLOW_SECONDS`では既存`final_follow_angles()`の終端形状と復帰処理へ切り替えるが、この境界frameも振り抜き区間に含める。終端形状へ切り替えた結果の実描画毛先Yにも前frame以上の単調性postconditionを適用し、`FOLLOW_SECONDS`直前→終端frameで上方向へ跳ね返らないこと。接触時の伸長メッシュをCOOLDOWN終端まで保持する方式は禁止する。
- `0 <= follow_seconds <= FOLLOW_SECONDS` の振り抜き中は、Passive Flexの柔軟chainを一時的に0へ固定し、ActionMotionの基準follow形状 + FollowThrough軌道を正とする。頭部回復加速度による二次反動をこの0.16秒へ重ねない。
- Passive Flexを0にしているframeではsoft chain内部状態を現在の基準形状へ同期する。振り抜き終了後にCOOLDOWNの柔軟追従を再開しても、古い角速度・offsetを持ち越して毛先を跳ね返さない。
- Active Strike中にPARRYへキャンセルした場合、直前の実メッシュから中心線を保存する。PARRY entryでは中心点座標を直接lerpせず、各segmentの長さと角度を個別補間してrootから再積算する。これにより向きの違うsegment同士のショートカットで弧長が基準長より短くなることを防ぐ。
- 断面はprofileの固定幅から毎frame再構築し、伸長中の弧長を滑らかに戻しながら断面幅を潰さない。
- 特殊な中心線補間は、**直前表示stateがSTRIKE**で、かつPARRY開始直前の実中心線長がprofile基準長より0.5%以上伸びている場合だけ有効化する。
- IDLE / CHARGING / WINDUP / COOLDOWNからのPARRYでは、中心線長に関係なく既存入口処理を使う。WINDUPの後方アーチをActive Strike伸長と誤認しない。
- **すべてのPARRY遷移で最初の1frame（parry_join≈0）は、直前の実427頂点をそのまま表示する。** WINDUPではPARRY開始時に柔軟chainが0へ切り替わるため、これをしないと見えていた柔らかい形が1frameで消えて形状ジャンプになる。
- 2frame目以降は、STRIKE中のActive Strike伸長から入った場合だけ中心線補間を続ける。それ以外のIDLE / CHARGING / WINDUP / COOLDOWNからは従来PARRY形状へ移る。
- `parry_join >= 0.999`では再構築を打ち切り、PARRY本来のtarget verticesをそのまま採用する。固定部境界の接線再計算で根元〜62%が動くことを防ぐ。
- ENTRY中心線から断面を再構築するときも、最終断面だけは平均接線ではなく「最終断面中心→tip」の最終edgeを基準にする。Active Strikeからの長い中心線を畳む途中でもtip三角形を反転させない。
- segment角度補間では、隣接segmentの角度差が「entry形状またはtarget形状の大きい方 + 0.03rad」を超えないよう前後2方向から制限する。ENTRY途中だけendpoint形状より鋭い局所折れを生成しない。

### Active Strike初期仕様

- active開始: STRIKE contact進行 q=0.18。
- Active turn/伸長の時計は全区間で同一にしない。弧長sが大きいほど開始・最大時刻を遅らせ、根元→中央→毛先の順に能動加速を伝える。
- 中央付近はq≈0.30から強くなる。
- 中央までは従来のactive timingを維持する。
- 弧長65%以降はdistal snap領域とし、毛先ほどactive開始を遅らせる。
- 毛先はq≈0.88まで通常の能動turn/伸長を強く抑える。
- さらに弧長70%以降へ**terminal snap**を追加する。terminal snapはq=0.90までは0、q=0.90→1.00で相手方向への追加turnを最大70%まで立ち上げる。
- 通常のActive turnだけを先に弧長方向へ2回平滑化し、前後2方向の隣接角度差0.045rad制限を通す。
- terminal snapはその後に弧長70%以降の滑らかな空間envelopeとして加える。追加後の隣接角度差0.045rad制限は**根元→毛先の1方向だけ**で行い、毛先の遅延加速を同一frameで中央・根元へ逆伝播させない。別レイヤで急折れさせず、かつ時間差を壊さない。
- 中央の速度ピーク後にterminal snap由来の別ピークを作り、120fpsでも少なくとも1frame以上ピーク時刻を分離する。
- 根元0〜12%: 能動turnを弱くし、頭部の勢いを残す。
- 12〜55%: 相手方向へ連続的にturn。
- 55〜100%: 最大turn。毛先が相手頭部へ向く。
- Active turnは区間ごとに独立適用せず、弧長方向へ2回平滑化する。
- 隣接区間のactive turn差は0.045rad以下へ制限し、メッシュの折れ・面反転を防ぐ。
- 通常攻撃の最大メッシュ伸長: 1.22倍。
- 最大チャージの最大メッシュ伸長: 1.45倍。
- 伸長は根元1.00倍→毛先側最大値へ滑らかに分布する。
- 1frameで長さを瞬間切替せず、qに応じてsmoothstepで増加する。
- 接触の「方向」と「距離」は分離する。通常STRIKEで接触直前にwhole-transformを動的再計算し続けず、中央と毛先を同時加速させない。
- q=0.90以降はActive Strike内で弧長70%より先の中心線へ**distal aim correction**を加える。補正は中心線各点を根元周りへ回転するだけとし、70%地点0→毛先1の滑らかな空間weightで、q=1ではtipの根元基準方向をtarget方向へ一致させる。
- distal aim correction後はprofile基準断面幅から427頂点を再構築する。中心線へ平行移動残差を足さず、通常1.22倍／最大チャージ1.45倍のActive stretchと弧長上限を維持する。
- 距離補正は、同じtarget・chargeでq=1のActive Strike形状を予測し、その最終tip長から必要なreach倍率を先に求める。MotionRootの軸方向reachは単一smoothstepではなく2段階で適用する。
- 前段reachはq=0.20→0.42で最終補正量の36%まで進める。これはrootの頭部初速後にmiddleを1frame以上遅れて加速させるための最小量とする。
- 後段reachはq=0.45→0.68で残り64%を適用し、tipの最大速度をmiddleより後へ残す。q=0.68以降は最終倍率へ固定する。
- 35%では1280/P2/通常攻撃でrootとmiddleの速度ピークが同frameに残り、36%で30/60/120fpsを含む全24描画ケースと120fps全8速度条件を維持したため、前段36%を採用値とする。
- reach軸はtarget方向を使い、terminal snap開始q=0.90より十分前に倍率変化を終える。接触直前にsource tip長から倍率を再計算し続けないことで、中央速度ピークを毛先終盤ピークへ巻き込まない。
- q=1ではActive Strikeのtip方向一致 + 固定済みreach倍率により接触点へ一致させる。120fps通常/最大チャージで根元→中央→毛先の速度ピークを少なくとも1frameずつ分離する。
- 確定Hit通知からの再提示は速度ピーク検査対象の攻撃進行ではなく、過去Hitをその場で正確に再表示する経路なので、ここだけはreach/turnの完全投影を許可する。接触後のFollowThroughも既存の固定接触点→終点投影を維持する。

この方式では「頭がアホ毛を運ぶ」のではなく、**頭が初速を与え、アホ毛自身がその初速へ追加加速して相手を叩く**ことを目標とする。

## 承認済み画像のGitHub正本化

2026-10-06にMacへ手動適用していた `ahoge_straight_head_update_v2` を再取得し、古いコードを上書きせず現在HEADへ素材差分だけを統合する。

- 承認PNGをバイト列そのままで `ahoge_straight.png` として追加する。
- PNG上の断面を `bind_vertices` とし、UVはbind形状へ固定する。
- ゲーム内の待機C字は `idle_pose_vertices` として独立させる。
- LONG_TESTのCharacterCatalogを直線素材へ切り替える。
- Deformerは直線Textureならstraight profile、旧Textureならlegacy profileを選択する。
- Texture path・寸法・file digestが一致しないprofileは使用しない。
- 専用のStraight asset / Head motion CIで実BattleHUD上の頭部・根元・接触まで検証する。

旧 `ahoge.png` は削除せず比較・回帰用に保持する。素材統合成功だけで柔軟chainのHuman Verificationを合格にしない。

## 検証

純粋な姿勢計算と、実BattleHUDを使う三動作の頭部並進・回転、根元の接続誤差、頭部横端の包含を検査する。通常/最大チャージ、左右、2解像度、30/60/120fpsで検査し、パリィ開始時の実姿勢の連続性と復帰を確認する。既存の接触・パリィ・三動作・振り抜き・モーションプレビュー・オンラインCIも確認する。
PNG出力と自動検査、CI実描画の確認、MacでのHuman Verificationを別に記録する。CIとMacが同じ承認Texture/Profileを使用していることを前提条件とする。

## 手元での調整

`battle_head_motion.gd`のキー値を一つずつ編集し、既存プレビューの「コード再読込」で比較する。

```bash
godot --path . res://tools/motion_preview/MotionPreview.tscn
```

画像承認を理由にモーション品質NGを解除しない。PR #105はHuman Verificationと独立最終レビューまで未マージとする。


## アホ毛根元の頭部固定契約

頭部とアホ毛の接続は、近似した移動量の加算ではなく、頭Sprite上の1つの固定アンカー座標を正本にする。

1. 頭部の位置、左右反転、表示倍率、回転を先に確定する。
2. 頭Spriteローカルの固定アンカー座標を、その最終TransformでCanvas座標へ変換する。
3. アホ毛Rigのローカル原点（メッシュ根元）を、そのCanvas座標と一致させる。
4. アホ毛の曲げ、伸長、パリィ、接触補正は根元より先のMotionRoot/Meshへ適用し、根元座標は動かさない。

この契約はIDLE、CHARGING、WINDUP、STRIKE、COOLDOWN、PARRYの全frameで共通とする。
頭部が±0.4D移動し、仰角が±30度へ変化しても、頭側アンカーとアホ毛根元の距離は描画座標で実質0を維持する。
左右反転・1280/1600・30/60/120fpsでも同じ座標変換を使用する。

実装では `FighterVisual.ahoge_head_anchor_canvas_position()` と `FighterVisual.ahoge_root_canvas_position()` を検査用にも公開し、同じframeで一致することを自動検証する。


### 頭画像表面アンカーへの修正

Human Verificationで、旧`crown_offset`をSprite Transformへ置き換えただけでは見た目が変化しないことを確認したため、固定アンカーの定義を修正する。

- 頭側アンカーYは固定表示オフセットでは決めない。
- 頭画像の透過を読み、頭幅の中央位置付近で上から最初にalpha>=0.5となる画像ピクセルを「生え際表面」とする。
- Xは頭画像の使用領域中央を初期値とする。左右反転はSprite Transformに任せ、P1/P2で別座標を持たない。
- 取得した画像ピクセル座標を固定し、各frameでは頭Spriteの最終TransformでCanvas座標へ変換する。
- アホ毛メッシュ根元をそのCanvas座標へ一致させる。
- 確認画面には頭側アンカーとアホ毛根元を別色のマーカーで表示し、重なったときに誤差0を目視できるようにする。

これにより、従来の「画像上端から34px」という近似位置を廃止し、実際に見えている頭髪表面へ接続する。


### 取り付け角度の頭部追従

Human Verificationで、根元位置だけを頭部アンカーへ固定しても、頭部の仰角変更時にアホ毛の根元方向が合わないことを確認した。

このため、根元接続は位置だけでなく姿勢も拘束する。

- `AhogePrototypeRig.position` は頭部アンカーと一致する。
- `AhogePrototypeRig.rotation` は同frameの `HeadSprite.rotation` と一致する。
- P1/P2の左右反転は既存のRig scaleで扱い、回転値そのものは頭部と同じ値を使う。
- `AhogeMotionRoot` の回転・伸長・メッシュ変形はRigの取り付け姿勢より内側で相対的に適用する。
- 首確認で後端-0.4D/+30°、中央0D/0°、前端+0.4D/-30°のどこでも、頭部の上方向とアホ毛Rigの上方向が一致する。
- 通常BattleのCHARGING/WINDUP/STRIKE/COOLDOWN/PARRYでも同じ契約を維持する。


## 段階調整4：ロング攻撃のための動的柔軟追従

頭部との接点位置・取り付け角度は固定できたため、次はロングタイプの攻撃モーションを成立させるために、根元より先の毛束へ動的な遅れとしなりを追加する。

この柔軟化の目的は待機中の揺れを増やすことではない。ロングタイプの「頭を後ろへ引く → 頭を先行して前へ振り出す → アホ毛の中間・毛先が遅れて追従し、後方から前方へ走って相手の頭を叩く」を実現するための共通描画層とする。NeckRangePreviewはその挙動を単独で観察・調整するための開発用治具であり、最終目的ではない。

### 旧方式の問題

旧方式は、頭部の現在角度に対して毛先側で一定割合を静的に打ち消し、小さな自然曲率を加えるだけだった。

- 頭部の移動速度を見ていない。
- 頭部の回転速度を見ていない。
- 前frameの毛束速度を保持しない。
- 根元・中央・毛先で応答速度がほぼ同じ。
- そのため柔らかさ0.0〜1.0を変えても、主に静止形状が少し変わるだけで、攻撃に必要な「遅れ」「反動」「根元から毛先へ伝わる波」にならない。

この静的補正だけを強くする方向は採用しない。

### 境界

- AhogePrototypeRigの位置は頭部接点へ同frameで固定する。
- AhogePrototypeRigの基準回転は頭部仰角へ同frameで追従する。
- 根元頂点は常にVector2.ZEROとし、頭部から離さない。
- 柔らかさはMotionRoot/Mesh内部の相対角度だけで表現する。
- server authoritativeの攻撃時間、接触時刻、Hit、Defense、Just、Clash、Ratingは変更しない。
- ActionMotionが持つCHARGING/WINDUP/STRIKE/COOLDOWNの基準形状を置き換えず、その上へ描画専用の動的柔軟オフセットを合成する。

### 動的柔軟モデル：時間遅延方式を廃止し、連結チェーン方式へ変更

2026-10-06 01:53のMac Human Verification録画では、前版より時間差そのものは確認できた。頭部が切り返した直後に毛先が旧方向へ残るframeは存在する。

しかし、各区間が「同じ頭部姿勢波形を時刻だけずらして再生」しているため、根元の運動が中央へ、中央の運動が毛先へ力として渡らない。結果として全体が順番に倒れる柔らかい板の見え方で、毛先側へ速度が乗るムチ打ちにならなかった。

このため履歴参照だけの時間遅延方式も不採用とし、**少数の連結control chainを持つ角度力学**へ変更する。

#### control chain

2026-10-06 19:51のMac Human Verificationで、毛先側は大きく振れる一方、根元〜中央がほぼ剛体のまま残り「毛先だけびよよーん」と見えることを確認した。原因はcontrol 0の角度を頭部へ完全拘束し、controlをほぼ等間隔で配置していたこと。

根元の**位置**だけを頭部へ完全固定し、根元直後の**角度**には回転自由度を持たせる。

毛束全体を弧長方向に9個のcontrol点へ代表させるが、配置は根元側を密にする。

- control target fraction: 0.00 / 0.02 / 0.05 / 0.10 / 0.18 / 0.30 / 0.45 / 0.65 / 1.00。根元側へさらに密にする。
- control 0: 根元直後の第1区間。位置は固定だが角度は頭部角度へばね追従し、完全拘束しない。
- control 1〜8: 直前controlのworld angleとActionMotion基準曲率を目標として追従する。
- 根元ヒンジは頭部の回転・並進加速度を受ける。offsetは先頭30%へ勾配付きで分布し、根元〜中央に連続した曲率を作る。
- 各controlは角速度を保持し、前のcontrolが動いた結果を次のcontrolが後から受け取る。
- 9 controlの動的offsetを毛束全区間へ弧長補間して描画する。
- 静止時は全controlが現在のActionMotion形状へ収束し、追加曲げを残さない。

根元頂点Vector2.ZEROは常に固定する。ここで柔らかくするのは根元**位置**ではなく、根元から出る第1区間の接線角度である。そのため頭部からアホ毛が外れることなく、根元から全体がしなる。

#### 頭部前後移動

頭部の回転だけでなく、前後移動もムチの駆動源とする。ただし速度そのものを曲げ量へ変換する方式は採用しない。

Human Verificationでは、速度driveを使うと前へ移動している間ずっとcontrol 1が一方向へ押され、根元側の大きな曲げが持続した。これは「柔らかい板が倒れる」見え方を強める。

新方式ではCanvas Xの**加速度**をdriveへ使う。

- 頭部が前方へ加速した瞬間、進行方向と逆向きの短いdrive angleをcontrol 1へ与える。
- 頭部が減速するとdrive符号が反転し、根元側が戻る一方で中央・毛先には直前の角速度が残る。これにより毛先の追い越しを作る。
- 等速移動中はdriveをほぼ0とし、根元を曲げ続けない。
- 通常Battleのworld-space chainではCanvas Xを扱うが、NeckRangePreviewの方向付き伸長targetはキャラクター前方基準のlocal chainとして扱う。NeckRange専用入力では前後位置を `_head_offset.x * facing`、取り付け角を `_head_rotation * facing` へ正規化し、P1/P2で同一の物理入力にする。左右反転そのものはRigのscale/rotationで描画する。
- driveは根元/control1/control2へ45/35/20%で分配し、根元側30%全体からしなりを開始する。
- control3以降へは結合を通して伝える。

#### 2026-10-07 Human Verification録画: directional chainの過大反動を不合格とする

MacのNeckRangePreview「攻撃速度テスト」録画で、後端→前端の切り返し中に毛束が輪になるほど折れ込み、その反動で左右へ大きく振り返すことを確認した。前端・後端も「ほぼ直線」へ十分収束する前に次の反転へ入り、要求するムチ打ちではない。

この録画を見た目の正本とし、従来の「待機C字曲率の55%以下なら端点合格」は廃止する。

- 後端保持と前端保持では、根元〜弧長75%の総曲率を0.20rad以下とし、ほぼ直線と判定できること。
- 後端ではlocal tip Xを基準弧長の-70%以上、前端では+70%以上まで伸ばす。local tip Yは基準弧長の15%以内に抑え、方向targetから大きく斜めへ逃げないこと。
- directional amount=1の間は待機C字の基準曲率をtargetへ持ち込まず、端点ではdirectional curve retention=0を正とする。
- 切り返し中も隣接segmentの角度差を制限し、中心線が輪・フック状に巻き込む局所折れを禁止する。根元→中央→毛先の時間差は維持し、全区間を同時に剛体回転させて解決しない。
- directional chainの折れ制限を**描画segment列へ同一frameで適用しない**。render時にrootからsegmentを順次clampすると、rootの新角度が同一frameでmiddle/tipへ伝わり、物理chainの位相差を消してしまう。
- 代わりに9個の動的control間へ最大角度差を設ける。各controlは自身の角速度とばね応答を保持したまま、直前controlとの差だけを上限内へ制限する。描画はそのcontrol列を弧長補間するだけとし、root→middle→tipの時間差を保持する。
- 0.27radのcontrol間上限ではroot→middleの位相差が不足し、30fpsでrootとmiddleが同じframeに前方反転した。一方、全controlを0.40radへ広げると実描画総曲率が約3.14〜3.20radまで増え、録画と同じU字巻き込みが再発した。どちらの一律値も不採用とする。
- root側0.43rad→tip側0.05radでは30fpsがroot 0.09→middle 0.15→tip 0.15となり、root先行は得られたがmiddle→tipの位相差が不足した。また実描画総曲率が2.397796radまで増え、2.20rad契約を超えたため不採用とする。
- 位相差を根元側へ偏らせず全長へ再配分し、NeckRange directional中のcontrol間角度差はroot側0.32rad→tip側0.18radの線形勾配を候補値とする。8段の最大差合計を約2.18radへ収めつつ、root→middleとmiddle→tipの両方へ遅れを確保する。
- 実描画の総曲率2.20rad以下、端点0.30秒内のほぼ直線収束、root < middle < tipの反転順序を同時に満たすことを採用条件とする。毛先→根元への逆伝播clampは禁止する。
- 30fpsでもrootとmiddleが同一frameへ潰れないよう、directional chainのspring gainは弧長後半ほど弱くする。root側の応答速度は維持し、middle/tipだけを1frame以上遅らせる。端点0.30秒内の直線収束を壊さない範囲でNeckRange専用tip spring gainを下げる。
- 端点の前後伸長量・斜め逃げ率は、待機C字の根元→毛先chord長ではなくprofile中心線の**基準弧長**を分母にする。C字のchord長を基準にして直線伸長を過大評価しない。
- root/chainの減衰をNeckRange専用tuningで引き上げ、directional rootの周波数と並進加速度driveを必要以上に強くしない。端点0.30秒内で収束する一方、0.15秒の切り返し中はroot→middle→tipの順序を残す。
- 承認済みidle C字では根元第1区間が約-150°を向くため、前方0°targetまで約2.6radの回転自由度が必要になる。従来のdirectional root最大offset=1.75radでは前方targetへ物理的に到達できず、約-50°で飽和していた。NeckRange directional中はroot/controlとも最大offsetをπ近くまで許可し、前後どちらのtargetにも対称に到達できることを必須とする。
- directional最大offsetの拡大はNeckRange専用tuningだけに適用し、通常Battleの共通defaultへはHuman Verification合格まで反映しない。
- このHuman Verificationが再合格するまで、NeckRange専用値をMotionPreview/Battle共通defaultへ昇格しない。

#### 現在の調整ゲート：NeckRangePreviewの根元〜中央を柔らかくする

2026-10-06 20時台のHuman Verificationで、頭の移動・仰角は合格だが、アホ毛は「根元〜中央が棒、毛先だけがびよよーん」と判定された。以後、**NeckRangePreviewで根元〜中央が十分しなるまで、MotionPreviewの攻撃形状そのものは変更しない。**

原因は2層あった。

1. 根元側の応答が速く、柔らかさが毛先へ偏っていた。
2. より本質的には、control間の目標曲率として待機C字の区間角度差を常時100%使っていた。そのため根元を柔らかくしても「柔らかいC字が揺れる」だけで、移動中にC字自体がほどけなかった。

NeckRangePreviewでは、単にC字曲率を弱めるだけでは不足する。2026-10-06 21時台のHuman Verificationで「前後に振っても丸まった形状を保つのはNG。後ろチャージ中は後方へ伸び、前方攻撃では前方へ勢いよく伸びる」が正本要件として確定した。

このため「攻撃速度テスト」は方向付き伸長targetを持つ。

- 後端保持: directional amount=1、direction=-1。毛束全区間の目標接線を後方へ揃え、ほぼ直線へ伸ばす。
- 前方切り返し: 頭部は従来どおり0.15秒で前へ移動する。アホ毛のdirection targetは頭部と同じsmoothstepで連続反転させず、最初の約22%は後方targetを保持した後、進行22%→62%の短区間で-1→+1へ急反転させる。これにより頭が先行し、rootが遅れて急加速する。
- directional target中のroot hingeは通常4.5Hzではなく9.0Hzで追従し、反転開始後だけrootへ明確な加速を与える。control 1〜8は絶対方向targetを直接受けず、直前controlから伝わった角度でのみ反転する。中腹・毛先は後方へ残り、後から前方へ加速する。
- 前端保持: rootはdirection=+1へ向く。control 1〜8はrootから順に伝播して前方へ揃い、最終的に毛束全区間がほぼ直線になる。
- directional amount=1の間、control 1〜8へ現在directionのabsolute targetを直接混ぜない。直接混ぜると中央・毛先がchainを飛び越えて同時反転するため禁止する。
- テスト停止/手動位置: directional amount=0。方向付き伸長を解除し、待機C字へ復元する。

directional target中は待機C字の局所曲率保持をほぼ0へ落とし、ActionMotionのsegment lengthは保つ。さらに描画時も「待機角＋offset」へ戻さず、control chainが保持しているworld angleを現在の取り付け角からlocal angleへ戻して直接補間する。これにより、後端/前端の保持中はほぼ直線、切り返し中だけcontrol間の位相差で曲がる。

つまり「C字のまま位置だけ移動」ではなく、同じ毛束長を使って **後方直線 → 遅れで一時的に曲がる反転 → 前方直線** へ変形する。

新しい目標:

- 根元頂点の位置は頭部anchorへ固定する。
- 根元直後の接線角度は頭部回転へ即追従せず、明確に遅れる。
- 弧長0〜30%で目視できる曲率が発生する。
- 中央部も根元に対して遅れて曲がる。
- 毛先だけが大振幅で振動する挙動を抑える。
- 頭停止後は全体が1本の柔らかい毛束として減衰する。

初期調整値:

- control数: 9。配置は 0 / 2 / 5 / 10 / 18 / 30 / 45 / 65 / 100%。
- 根元ヒンジ固有周波数: 4.5Hz。
- 根元ヒンジ減衰比: 0.34。
- 根元ヒンジ動的offset上限: 0.36rad。
- 根元ヒンジの曲げを弧長先頭30%へ分布する。
- 根元先頭区間ではroot offsetの35%から開始し、30%地点までに100%へ移す。根元から中央へ角度差を作り、剛体回転にしない。
- 隣接区間の動的offset差上限: 0.045rad。
- chain固有周波数: 5.2Hz。根元〜中央の追従をさらに遅くする。
- 根元側減衰比: 0.38。
- 毛先側減衰比: 0.90。毛先だけの往復振動を強く抑え、30fpsでも中央より遅れて反転させる。
- 隣接control相対速度減衰: 根元0.18 → 毛先0.90。隣より速く動きすぎる局所振動を吸収し、一本の毛束として動かす。
- ActionMotion基準形状への直接復元: 0.018。
- 毛先spring gain: 0.45。30fpsで中央と同frame反転したため、毛先だけ応答を遅らせる。
- 高速移動時のC字曲率保持率: 0.12。方向付き伸長targetが無い場合の補助。
- 方向付き伸長時のC字曲率保持率: 0.03。
- 方向付き伸長のroot hinge固有周波数: 9.0Hz。通常の柔らかさ4.5Hzとは分離し、前方切り返し時だけ鋭く反転する。
- 方向付き伸長の根元角度上限: 1.75rad。
- 方向付き伸長の全体動的offset上限: 2.40rad。
- 曲率解放activityの基準: 前後速度1500px/s、角速度6rad/s、加速度drive上限。
- 前後加速度drive: 0.000012rad / (px/s²)。
- drive上限: 0.65rad。
- drive配分: 根元45%、control 1へ35%、control 2へ20%。入力を根元側30%へ分散する。
- 動的offset上限: 0.65rad。
- 数値積分substep上限: 1/240秒。

これらは見た目専用の初期値。毛先を速くするために単純な先端角度倍率を掛けるのではなく、角速度がchainを通って伝わった結果として毛先のピーク速度が根元・中央より後に出ることを確認する。

この調整値は `src/ui/neck_range_fighter.gd` の `NECK_SOFT_TUNING` を正本とし、NeckRangePreviewでActionMotionをconfigureした直後に1回だけ `set_soft_tuning()` で適用する。毎frame再適用して慣性状態をresetしない。MotionPreview/BattleのActionMotionにはこの専用profileを適用しない。

### 柔らかさ0.0〜1.0

柔らかさは単なる角度倍率ではなく、動的追従の強さとして扱う。

- 0.0: control chainを現在の基準形状へ同期し、動的offsetを描画しない。
- 0.5: chainで計算した動的offsetを50%描画へ合成する。
- 1.0: chainの動的offsetを100%描画へ合成する。
- 柔らかさを変更してもActionMotionの生の角度列やserver判定は変更しない。
- 静止時は0.0と1.0のどちらも同じ基準形状へ収束する。違いは運動中の位相・速度・反動として確認する。

### ロング攻撃への合成

段階調整中はNeckRangePreviewの係数を通常Battle/MotionPreviewから隔離する。0.0〜1.0の柔らかさ入力インターフェースは共通だが、NeckRangePreviewだけが未承認の実験用tuning profileを使用する。Human Verification合格後に係数を共通defaultへ昇格する。

- IDLE: 100%。
- CHARGING: 0%。最大溜めの後方アーチと長押し静止を正とし、chainは現在姿勢へ同期する。
- WINDUP: 45%。最大溜めを壊さず、前方切り返し直前からchainを立ち上げる。
- STRIKE: 100%。頭部加速・減速から最大の伝播を出す。
- COOLDOWN: 100%。振り抜き後の反動を保持して減衰する。
- PARRY: 現段階では0%。既存の局所先端払いを維持する。
- ROUND_LOCKED・アホ毛非表示: 動的状態を破棄する。

MotionPreviewの0.0〜1.0入力は残すが、現段階では共通default係数を使う。NeckRangePreviewの実験係数を自動で参照しない。NeckRangePreviewがHuman Verification合格した時点で、その係数セットを共通defaultへ1回の昇格変更として反映する。

攻撃では次の見え方を狙う。

1. CHARGING/WINDUP: 既存の後方アーチへ収束し、最大溜めでは完全に静止する。
2. STRIKE序盤: 直前frameの後方姿勢を基準に頭部と根元が先行して前進し、中間・毛先は後方へ残る。
3. STRIKE中盤: 根元側の遅れが先に解け、中央へ伝わる。
4. 接触直前: 毛先側の遅れが解放され、既存の接触投影と合成して相手頭部へ到達する。
5. 接触後: 既存FollowThroughを維持しつつ動的角速度を残し、直線の棒として戻さない。
6. COOLDOWN: 振り抜き終端から待機形へ減衰しながら戻る。

接触投影・振り抜きで参照する頂点は実際の柔軟補正済み頂点と同じものを使う。見た目を柔らかくしても接触誤差2px以下の契約は維持する。

### NeckRangePreview

NeckRangePreviewを現在の最優先Human Verificationゲートとする。ここで「頭＋アホ毛」の基礎モーションを完成させるまで、MotionPreview/Battle側の柔軟係数は更新しない。NeckRangePreviewでは専用の実験用tuning profileを使い、Human Verification合格後にそのprofile値を共通defaultへ昇格し、MotionPreviewへそのまま反映する。

- 手動の後端/基準/前端ボタンは位置・根元固定確認として残す。
- 旧4秒sin往復は慣性確認には遅すぎるため廃止する。
- 「攻撃速度テスト」は、後端-0.4Dで約0.30秒保持 → 約0.15秒で前端+0.4Dへ切り返し → 約0.30秒保持 → 約0.30秒で後端へ戻す周期とする。
- 前方切り返し区間で、柔らかさ0.0と1.0を比較する。
- 1.0では根元が即座に頭へ追従し、control chainを通じて中央、毛先の順に反転すること。
- 頭部が前端で停止した後も中央・毛先の角速度が残り、毛先側が遅れて前方へ走った後に減衰すること。
- 根元・中央・毛先の最大前方角速度ピークが同frameにならず、根元→中央→毛先の順になること。
- 静止端点の0.0/1.0差を柔らかさの主な合格条件にしない。
- 「柔らかさを大きくするとC字のまま全体回転する」挙動は禁止する。
- 後端保持では毛先が根元より後方へ十分離れ、前端保持では毛先が前方へ十分離れること。
- 後端/前端の保持中は、待機C字の0〜75%区間の総曲率を50%以下まで解放すること。

### 検証

- 根元頂点は常にVector2.ZERO。
- 頭部アンカーとメッシュ根元の誤差0.01px未満。
- 頭部とRigの取り付け方向差は実質0度。
- 柔らかさ0.0では描画遅延補正が0。
- 静止して0.20秒以上経過した端点では、柔らかさ0.0と1.0の差は小さく収束する。
- 後端から前端へ約0.15秒で切り返したとき、柔らかさ1.0では根元→中央→毛先の順に反転する。
- 根元・中央・毛先の最大前方角速度ピーク時刻が根元→中央→毛先の順になる。
- 毛先のピーク角速度が中央より小さすぎず、少なくとも明確な追い越し感を作れること。
- 0.0では同じ高速切り返しでも追加のchain運動を描画しない。
- 前端保持後はchainの角速度が減衰して基準形状へ収束する。
- 30/60/120fpsで根元固定と伝播順序を維持する。
- CHARGING/WINDUP/STRIKE/COOLDOWNでも全頂点有限、頂点数・UV・index・mesh RIDを維持する。
- 既存の接触2px、振り抜き、画面内包含、三角形反転防止、オンライン回帰を維持する。
- 自動試験合格だけでモーション品質合格とせず、Macの等倍再生でHuman Verificationする。


#### 2026-10-07 19:42 Human Verification: Passive FlexだけでなくNeckRange専用Active Driveを加える

Mac録画では、頭部の後退・前方切り返し・0.4D位置・仰角は意図どおりだが、アホ毛は頭部へ遅れて付いてくる受動chainの比率が高く、攻撃主体としての「溜め」と「打ち出し」が不足している。以後、頭部モーションは変更せず、NeckRangePreview専用にPassive Flexの上へActive Driveと弾性伸縮を重ねる。

採用する見え方は次のとおり。

- 後端保持では、後方targetへ伸びた状態を維持しつつ、毛束をわずかに圧縮して弾性エネルギーを溜める。待機C字へ戻したり、毛先だけを引き伸ばしたりしない。
- 前方切り返しでは、頭部が先に動く既存0.15秒のHead Driveを維持する。アホ毛のroot→middle→tipの位相差も維持する。
- Passive Flexだけに任せず、切り返し進行に応じた**能動target**をcontrolへ順次開く。root側から開始し、中央、毛先の順に前方targetへ自力で加速する。
- 能動targetを全controlへ同時適用して剛体回転させない。各controlのactive開始時刻は弧長方向に遅らせる。
- 毛先側ほど**慣性係数（mass）を大きくする**。これにより切り返し直後は毛先が旧方向へ残り、遅れて運動量を持つ。
- 毛先側はactive開始後の駆動gainも増やす。重いだけで遅れ続けるのではなく、中央より後に大きな速度ピークを作る。
- 前方へ振り出す間は毛束長を弧長方向に最大約10%伸ばす。伸長量はroot≈1.00からtip側へ滑らかに増やし、断面幅と根元固定を維持する。
- 前端保持では最大伸長を短時間保持した後、約2%程度の残留伸長へ減衰させる。停止/resetでは伸長を0へ戻し、待機C字へ自然復帰する。
- 伸縮はメッシュ全体のuniform scaleで行わず、segment lengthだけを弧長方向に変化させる。
- directional control間の折れ上限は、前候補0.43→0.05ではなくroot 0.32rad→tip 0.18radへ再配分する。Active Driveを加えても切り返し総曲率2.20rad以下を維持する。
- Human Verification合格前は、このActive Drive・mass・伸縮値をMotionPreview/Battle共通defaultへ昇格しない。既存BattleのActive Strike、PARRY、FollowThroughは変更しない。

初回Active Drive CIでは毛先の前方速度は中央を十分上回った一方、30/60fpsでrootとmiddleの速度ピークが同frame、middleとtipの前方crossも同frameになった。駆動力不足ではなくactive開始時刻が中央側で早すぎるため、gainや速度上限を下げず、active waveの時刻だけを再配分する。

- control 1〜8のactive開始は進行qに対し `0.30 + 0.55 * s` を基準とする。
- active fully drivenは `0.50 + 0.50 * s` を基準とする。
- root近傍は既存Head Drive直後に動ける一方、中央はq≈0.60以降、毛先はq≈0.82以降まで直接駆動を待つ。
- これによりroot→middle→tipの速度ピークと前方crossを30fpsでも別frameへ分離する。
- 毛先のmass増加・後段drive gain・弾性伸長は維持し、得られたtip速度優位を失わせない。

2回目CIでは、Active Driveの開始を後ろへ移しても30/60fpsのroot・middle速度ピーク時刻は変わらず、60fpsのtipピークだけが0.1167秒→0.1333秒へ遅れた。したがってmiddleの早すぎる追従はActive DriveではなくPassive Flexの結合ばねが支配している。

- directional中の結合ばねgainを単純なroot→tip線形補間にしない。
- 根元〜弧長30%は強い結合を維持し、頭部初速を受け取る。
- 弧長55%のmiddleではgainを0.56まで落とし、rootの速度ピークを同frameでコピーしない。
- middle→tipは0.56→既存tip gain 0.45へ緩やかに落とす。tipを極端に弱くして遅れ続けさせない。
- この3領域gainはNeckRange専用tuningとし、共通defaultは従来の線形gainのままとする。
- control間角度差0.32→0.18、総曲率2.20rad上限、Active tip mass 1.60、Active tip drive 1.75、弾性伸縮は維持する。

3領域spring gain（middle=0.56）のCIでは後端曲率が0.266423radまで増えて0.25rad契約を破り、root/middleの速度ピーク時刻も改善しなかったため不採用とする。directional spring gainは従来のroot→tip線形補間へ戻す。

次の原因はcontrol間折れ制限の参照時刻にある。現在はcontrol Nを更新するとき、同じ1/240秒substepですでに更新済みのcontrol N-1角度を基準にclampしている。このためspringで遅らせても、clampが新しいroot角度を同一substep内で後段へ押し流し、middle/tipの位相差を潰す。

- NeckRange directional中だけ、control間clampの上流基準を**直前substepのcontrol N-1角度**へ切り替える。
- control N自身のばね・速度更新は従来どおり行う。変更するのは折れ上限の参照時刻だけ。
- これにより折れ制限はU字抑止として残る一方、rootの新角度は1 controlあたり少なくとも1 substep遅れて伝わる。
- 1/240秒内部step・9 controlsでは、root→middle→tipへ数ms〜数十msの因果的な位相差を作り、30fpsでも別frameへ分離できる余地を持たせる。
- 参照を遅らせても実描画総曲率2.20rad以下、後端/前端0.25rad以下の契約は維持する。

完全な前substep参照（current carry=0）のCIでは、後端tipがY=-272pxまで斜めに外れ、後端曲率0.282818rad、切り返し総曲率3.42〜3.81radとなったため不採用とする。完全遅延は折れ制限を実質的に弱めすぎる。

次は上流参照角を「前substep→現substep」の補間にする。

- carry=1.0は従来どおり現substepの更新済み上流角を100%使用する。
- carry=0.0は不採用になった完全前substep参照。
- NeckRange専用ではroot側carry=0.92、tip側carry=0.78を弧長方向に補間する。
- 根元側は折れ抑止をほぼ従来強度で維持し、毛先側だけ同一substep伝播を22%抑える。
- rear/front保持で上流角が静止すれば前substep角と現substep角は一致するため、端点直線性そのものは変えない。
- 切り返し中だけ数msの追加位相差を作り、middle/tipの同frame反転を分離する。
- carry調整で2.20radを超える場合はcarryを1.0側へ戻す。曲率閾値は変更しない。

部分遅延carry=0.92→0.78のCIでも、30fps曲率2.224806rad、60fps 2.390293rad、120fps 2.459298radへ悪化し、30fpsのcrossは0.09→0.12→0.12のままだった。Passive Flex側の伝播遅延を増やしてHuman要件を満たす方向はここで不採用とし、clamp参照は従来carry=1.0へ戻す。

Human要望の「アホ毛自身が攻撃する」はPassive Flexの遅れ量ではなく、独立したActive Strike層で作る。

- Passive Flexは端点直線性・U字防止を満たす安定設定へ戻す。
- Active Strike層は、現在のsoft chain角度へ**弧長連続の進行波target**を混ぜる。
- wave targetは後方角-π→前方角0を滑らかに補間する。弧長sが大きいほどwave中心時刻を後ろへずらす。
- root近傍にはほぼ掛けず、middleから徐々に強くし、tip側で最大weightにする。
- middleは切り返し後半で自力加速し、tipはさらに後半まで後方慣性を残した後にスナップする。
- phase centerとweightはいずれも弧長方向のsmoothstepで連続化し、区間ごとの離散的な「板倒し」にしない。
- 初期候補はtip wave weight=0.72。phase centerはs≈0.25でq≈0.56、tipでq≈0.84へ連続的に遅らせ、時間幅±0.22で滑らかに遷移する。
- q≈0.60ではtip targetを後方に残すが、最大weightを0.72へ抑えることでroot-tip角差を約2.2rad以内へ収める。
- q→1ではwave target=0へ収束し、前端保持のほぼ直線形状を壊さない。
- 既存のActive tip mass / drive gain / 弾性伸長を併用し、wave解除時に毛先の速度ピークを最大化する。
- Active waveの共通default weightは0。Human Verification合格まではNeckRange専用値だけを有効にする。

tip wave weight=0.72のCIではtip速度が約55,480px/sまで上がった一方、総曲率が5.08〜5.70radへ増大した。絶対角度targetをrender角へ混ぜる方式は、攻撃力を作れてもU字禁止契約と両立しないため不採用とする。

能動エネルギーの後段集中は**角度ではなくsegment lengthの弾性解放**で作る。

- Passive Flexの角度生成・control clampは安定版へ完全に戻す。
- 後端保持では遠位側segmentを最大3.5%圧縮して溜める。
- 前方切り返しでは、各segmentの圧縮→伸長解放時刻を弧長sで連続的に遅らせる。
- release center初期候補は `q = 0.42 + 0.46 * s`。弧長20%付近q≈0.51、middle q≈0.67、tip q≈0.86。
- 各releaseはcenter±0.10のsmoothstepとし、離散的なsegment切替を避ける。
- release前はpreload contraction=-0.035を維持し、release後は既存の時刻別elastic stretch target（最大+0.10）へ追従する。
- 30fpsではroot側の解放をq≈0.6、middleをq≈0.8、tipをq≈1.0へ分け、伸長速度ピークをroot→middle→tipへ並べる。
- 角度を変更しないため、総曲率2.20rad契約はPassive Flex安定版の値を維持する。
- front holdではactive progress=1なので全segmentが解放済みとなり、+10%→+2%へ自然減衰する。
- reset/停止では伸長0へ戻し、待機C字へ復帰する。
- segment lengthの変化だけを使い、uniform scale・断面幅変更・根元移動は行わない。

段階的なlength解放のCIでは曲率・端点・伸長量は合格したが、30/60fpsのcross時刻は0.09→0.12→0.12から変わらず、middle速度ピークもrootと同frameに残った。長さ方向の弾性だけではPassive Flexの角度伝播を押し返せない。

次に、先端重量を**control物理内のinertial hold**として表現する。

- render後処理ではなく、control 1〜8のtarget計算内で作用させる。
- forward strike中、release前のcontrolは現在のcoupled targetへ加えて後方角-πへ戻ろうとする弱いhold torqueを受ける。
- holdは弧長30%まではほぼ0、middleから増え、tip側で最大とする。
- holdはq≈0.08→0.35で立ち上げ、q≈0.72→0.96で消す。
- 各control固有のActive Driveが立ち上がるほど `1 - active_section` でholdを解除し、後方保持→前方自力加速へ連続的に移る。
- 初期候補の最大hold gainは0.55。共通defaultは0。
- hold後のactual world angleには既存のcontrol差0.32→0.18rad clampを必ず適用する。したがって「重い毛先」を理由にU字上限を無効化しない。
- tip mass 1.60、tip drive 1.75、段階弾性解放を併用し、hold解除後の速度ピークをmiddle→tipへ順に作る。
- 30fpsの目標はroot q≈0.6、middle q≈0.8、tip q≈1.0付近の順に最大前方速度/前方crossを分離する。

inertial hold gain=0.55のCIでもcross時刻は変わらず、30fpsでは速度ピークが0.09/0.09/0.09へ寄るcaseも発生した。これ以上hold/spring値を推測で変更しない。

次調整の前に、canonical case（1280 / P1 / 30fps）で各sweep frameの以下を記録する。

- q / direction / elastic stretch
- root・middle・tipの実描画centerline X
- root・middle・tipのframe間前方速度
- soft control world angle

このframe traceから、middleの0.09秒ピークを0.12秒へ移すために必要な後段能動量と、tipを0.12秒でX<=0に留め0.15秒で解放するために必要な変位量を算出する。閾値側は変更しない。

frame traceでは0.12秒時点の実描画Xがmiddle=+451px / tip=+520pxだった一方、tip側soft control角は約-68°でまだ明確に遅れていた。実描画pointの絶対Xは「上流区間の累積前進 + segment伸長」を含むため、局所的なroot→middle→tip角度伝播の時刻指標としては不適切である。

検証軸を再分離する。

- **角度伝播のcross時刻**: profile基準segment長を用いる `_soft_chain_points` で測る。elastic stretchを混ぜない。これは本チャット開始前の正本と同じ。
- **角速度ピーク時刻**: soft controlのangular velocityをroot / middle / tip controlで測る。上流区間の累積並進を混ぜない。
- **見た目の伸縮**: 実描画mesh centerlineの弧長ratioで別に測り、1.04〜1.07を維持する。
- **毛先の実速度優位**: 実描画pointの最大前方速度 magnitude はtip >= middle * 1.08を維持するが、そのpeak時刻は局所角速度の位相判定へ使わない。
- これは閾値緩和ではなく、角度・伸縮・累積位置という別物理量を混ぜないための測定修正である。

また、inertial hold gain=0.55はcross改善がなく30fpsのtip速度peakを早めたため不採用とする。先端重量はactive_tip_mass=1.60で表現し、hold torqueは削除する。

control間折れ上限は引き継ぎ時の候補どおり3領域化する。

- root側: 0.32rad
- middle（s=0.55）: 0.22rad
- tip側: 0.05rad
- root→middle、middle→tipをそれぞれsmoothstep補間する。
- 旧0.43→0.05のtip遅延特性を残しつつ、root側を0.32へ絞って総曲率を2.20rad以下へ落とす。
- 目標は30fpsでcross/角速度peakともroot < middle < tipを成立させること。

3領域値0.32 / 0.22 / 0.05の初回CIでは、角速度peak順・毛先実速度優位・総曲率・端点・伸長は全PASSし、crossだけ30/60fpsで0.09→0.12→0.12（60fpsは0.100→0.1167→0.1167）が残った。120fpsはcrossもPASSしている。

値ではなく空間分布を調整する。

- 現状はmiddle=0.22からtip=0.05への補間がs=0.55→1.00全域に広がり、s=0.65付近でも約0.20radと緩い。
- root→middle補間はs=0.00→0.45で0.32→0.22。
- middle→tip補間はs=0.45→0.75で0.22→0.05。
- s>=0.75は0.05radを維持する。
- これにより95%位置を構成するdistal 25%をまとまった遅延領域にし、middleの0.12秒crossを維持したままtipだけ次frameへ送る。
- 上限値を増やさないため、総曲率2.20rad契約は維持または改善する方向である。

distal 25%を0.05radへしたCIでも、他条件は全PASSのままcrossだけ30/60fpsでmiddle=tipとなった。tip側をさらに遅らせる調整は脱力や長い残留を再発させるため行わない。

代わりにAhoge directional targetの切り返し開始を前倒しする。

- 頭部Head Driveは従来どおりq=0から0.15秒かけて-0.4D→+0.4Dへ移動する。頭部仕様は変更しない。
- アホ毛は頭部開始後15ms（q=0.10）まで後方targetを保持し、頭が必ず先行する。
- directional targetの-1→+1反転区間をq=0.10→0.50とする。時間幅0.40qは旧0.22→0.62と同じため、targetの反転速度自体は増やさず開始時刻だけ18ms前倒しする。
- 30fpsではu=0.4 frameでrootへ正方向targetを与え、root crossを0.06秒付近へ、middleを0.09秒付近へ前倒しする。distal 25%の0.05rad領域によりtipは0.12秒付近を維持することを狙う。
- 60fpsでも同様にroot < middle < tipのframe分離を作る。
- 「頭が先に切り返す」は、頭部q=0開始に対しアホ毛target q=0.10開始なので維持する。

自動検証は、既存の「後方/前方ほぼ直線」「root < middle < tip」「切り返し総曲率<=2.20rad」に加えて次を確認する。

- 前方切り返し中のcenterline弧長が基準より増え、全長では1.04〜1.07倍、最遠位segmentでは最大約1.10倍の範囲に入る。
- root/middle/tipの前方速度ピークはroot→middle→tipの順となる。
- tipの最大前方速度はmiddleより明確に大きくなり、毛先へ力が集まる。
- 後端の溜めでは過伸長せず、前方攻撃時だけ最大伸長へ移る。
- 停止後は伸長0・待機C字へ戻る。

この層の目的は、**「頭に運ばれる紐」から「頭で初速を得て、自分でも加速し、先端へ運動量を集めて叩く毛束」へ見え方を変えること**である。


#### 2026-10-07 direction target前倒し案の棄却

Active Driveの位相再配分後、direction target自体を22%→62%反転から10%→50%反転へ18ms前倒しした試行では、30fpsの前方crossが root/middle/tip = 0.09/0.09/0.09 となり、全長同時反転へ悪化した。60fpsでも root 0.0667 / middle 0.10 / tip 0.10 となった。

このためdirection targetの前倒しは不採用とし、従来の「頭部が先行し、アホ毛は序盤22%を後方保持、22%→62%で反転」を維持する。Active Driveの弧長別開始時刻だけで速度ピークをroot→middle→tipへ分離する。

direction targetの開始を早めてcross時刻を合わせる方法は禁止する。cross順序はPassive chainの伝播と毛先側慣性で作る。

direction targetを従来時刻へ戻した上で、middle→tipが同frameに残る場合は毛先側慣性だけを微増する。NeckRange専用active tip massは1.60→1.90を次候補とし、active tip drive gain=1.75は維持する。これにより毛先は前半でさらに1frame遅れ、後半では既存の能動driveにより中央を上回る速度で前方へ抜ける。


#### 2026-10-08 middle→tip同frameの原因切り分け

NeckRange専用active tip massを1.60→1.90へ増やしても、30fpsの前方crossは root/middle/tip = 0.09/0.12/0.12、60fpsは0.10/0.1167/0.1167のままで変化しなかった。一方、速度ピーク順序・毛先速度優位・弾性伸長・総曲率2.20rad以下は合格している。

したがって残件は毛先の質量不足ではなく、directional control間角度差clampが同一積分substepで**更新済み上流control角度**を参照していることによる下流への即時伝播と判断する。

- spring/coupling targetは従来どおり前substepの `previous_world[control - 1]` を参照する。
- directional control差clampも、NeckRange専用では同じ `previous_world[control - 1]` を参照する。
- 同じsubstepで更新した `_soft_world_angles[control - 1]` を下流clamp基準に使わない。これによりclamp自身がrootの新角度をmiddle→tipへ一気にコピーすることを防ぐ。
- 通常Battle/MotionPreviewの共通defaultは変更しないため、この挙動はtuning flagでNeckRange専用に有効化する。
- 既に合格しているtip速度優位、active drive、伸長、端点形状、総曲率上限は維持する。
- 採用条件は30/60/120fpsすべてでroot < middle < tipを維持し、端点0.30秒内に前後ほぼ直線へ収束すること。


#### 2026-10-08 同一step伝播抑制の結果と部分伝播

前substepの上流角を100% clamp基準にした試行では、30/60/120fpsすべてでroot < middle < tipの前方cross順序が合格し、速度ピーク順序・毛先速度優位・伸長条件も維持した。一方、切り返し最大総曲率が3.48〜3.60radへ増え、2.20rad契約を大幅に超えた。

これは「更新済み上流角を100%使うと位相差が不足」「前substep上流角を100%使うと位相差が過大」という両端が確認できたことを意味する。

次候補はclamp基準上流角を、前substep角→現在substep角の途中へ置く。

- 共通defaultは現在substep角100%（blend=1.0）のまま。
- NeckRange専用候補は `directional_clamp_upstream_blend=0.60`。
- `upstream_for_clamp = lerp_angle(previous_world[control - 1], _soft_world_angles[control - 1], blend)` とする。
- blendを0へ寄せるほど位相差が増え、1へ寄せるほど折れが減る。テスト閾値は変更しない。
- 採用条件は、root < middle < tip と最大総曲率<=2.20radを同時に満たすこと。速度ピーク・伸長・端点形状も従来条件を維持する。


#### 2026-10-08 部分伝播案の棄却とdistal遅れへの切替

clamp上流角blend=0.60では、60/120fpsのroot < middle < tipは分離したが最大総曲率が約2.69〜2.70radとなり、30fpsは依然0.09/0.12/0.12でmiddleとtipが同frameだった。全controlへ上流遅延を入れる方法はU字抑制と30fps位相差を同時に満たせないため不採用とする。

次はclamp上流角を共通従来値blend=1.0へ戻し、distal側だけに小さな角度自由度を与える。

- root側0.32rad、middle 0.22radは維持する。
- tip側control差上限を0.05radから0.09radへ広げる候補とする。
- tip側上限を狭くしすぎると、更新済み上流角へ毛先がclampで強制的に吸着し、massを増やしてもmiddleと同frameでcrossする。
- distalだけ0.09radまで旧方向へ残る自由度を与え、毛先自身のmass=1.90と後段Active Driveで次frameに前方へ抜けさせる。
- 全chainの上流角を遅らせないため、U字を作る大域的な位相差は増やさない。
- 採用条件は従来どおり最大総曲率<=2.20rad、root < middle < tip、速度ピーク順序、tip速度優位、伸長・端点条件の同時合格とする。


#### 2026-10-08 distal 0.09rad試行と0.18rad候補

clamp上流blend=1.0へ戻し、tip側control差上限を0.05→0.09radへ広げた試行では、最大総曲率・速度ピーク・伸長条件は合格したが、cross時刻は30fps 0.09/0.12/0.12、60fps 0.10/0.1167/0.1167のまま変化しなかった。0.09radではdistal controlがまだ上流へclamp吸着している。

次候補はtip側0.18radとする。

- root 0.32rad → middle 0.22rad → tip 0.18radの3段階分布とする。
- 9 control間8差の上限総和は概ね2.1rad以下に収まり、描画総曲率2.20rad契約と整合する設計範囲である。
- 全chainの伝播時刻は遅らせず、distalだけ旧方向へ残れる角度幅を増やす。
- tip mass=1.90、tip Active Drive=1.75を維持し、遅れた毛先が次frameで中央より高速に前方へ抜けることを狙う。
- テスト閾値は変更しない。


#### 2026-10-08 distal角度拡張の棄却と伸長タイミングの後段化

tip側control差上限を0.18radまで広げても、30/60fpsのcross時刻は0.09/0.12/0.12、0.10/0.1167/0.1167のまま変化しなかった。さらに後端保持曲率が0.262radとなり0.25rad契約を超えたため、distal角度上限の拡張は不採用とし0.05radへ戻す。

残る位置crossの同frame化は、切り返し中の弾性伸長タイミングを見直す。

現状はSTRIKE swingのほぼ全域でpreload -3.5%からstretch +10%へ解放しており、middleが前方へcrossする時点で遠位segmentが既に伸び、tip位置を同frameで前方へ押し出している。

新しい弾性解放:

- 後端保持では-3.5%のpreload contractionを維持する。
- swing前半〜中盤は収縮を保持し、頭部→root→middleの角度伝播を先に行う。
- stretch解放はswing進行q≈0.68から開始し、q=1.0で+10%へ到達する。
- これによりmiddleが先に向きを変え、distalは短いまま旧方向へ残る。
- swing後半でdistalが前方へ向き始めたところから一気に伸び、Active Driveと合成してtipの最終速度ピークを作る。
- 前端保持では+10%から+2%へ減衰し、resetで0へ戻す。
- 角度chainのroot 0.32 / middle 0.22 / tip 0.05、clamp upstream blend=1.0へ戻す。
- 最大伸長量・速度ピーク・総曲率・端点条件のテスト閾値は変更しない。


#### 2026-10-08 distal弾性preload量の調整

弾性解放時刻をswing後半へ寄せても30/60fpsのtip位置crossは変化しなかった。read-backの結果、ActionMotion側では既に弧長別の解放時刻 `release_center = 0.42 + 0.46 * s` を持ち、tipはactive q≈0.78〜0.98で遅れて解放される構造になっている。

したがって位相構造は維持し、preload contraction量を-3.5%から-6.0%へ増やす。

- -6%は最遠位segmentの最大値であり、根元側は弧長weightにより小さい。全centerlineの短縮は数%に留める。
- 後端では方向として十分後方へ伸びたまま、長さ方向にだけ少し縮んで弾性エネルギーを持つ。
- middle付近はq≈0.6〜0.8で先に解放し、tipはq≈0.78〜0.98まで圧縮を残す。
- 曲げ角は増やさないため、U字抑制と総曲率2.20rad契約を維持する。
- tipが前方へ向いた後に収縮が解けて+10%伸長へ移ることで、位置crossを1frame遅らせつつ終端速度を増やす。
- 後端centerline長は基準の96%以上、最大前方伸長は従来の1.04〜1.07倍を維持する。


#### 2026-10-08 cross判定と弾性伸縮の責務分離

30/60fps crossが伸長時刻・preload量の変更で一切変化しなかったためテスト実装を再確認した。cross判定は `_soft_chain_points()` が `_softened_angles(rest_angles)` と基準segment長 `_lengths` だけで中心線を再構築しており、弾性伸縮済みmesh長は使用していない。

このためcross順序は純粋な**角度波伝播の契約**であり、伸縮量で合わせてはいけない。

- preload -6%試行はcross修正には無効なので不採用。NeckRange専用preloadは-3.5%へ戻す。
- swing後半で+10%へ伸ばす弾性表現自体は、攻撃の勢い表現として維持する。
- cross修正は角度chainだけで行う。

新しい角度波は「wave arrival前のhold → arrival後のActive Drive」とする。

- 各controlのwave到達時刻は弧長sに応じて遅らせる。
- wave到達前はtargetをそのcontrolの前substep角へ寄せ、旧方向の角度状態を短時間保持する。
- wave到達後は既存coupling + Active Driveへ滑らかに解放する。
- rear/frontの静止保持ではwave holdを残さない。
- hold中に上流clampへ吸着して位相が消えないよう、forward swing中だけdistal control差上限を0.18radまで許可する。rear/front保持は0.05radを維持する。
- 3段階上限はroot 0.32 / middle 0.22 / distal-active 0.18で、総曲率2.20rad契約を超えないことをテストで確認する。
- 共通defaultではwave hold強度0、active distal stepは通常tip stepと同値とし、NeckRange専用tuningだけ有効化する。


#### 2026-10-08 Active wave holdの実装候補

cross判定が純粋な角度波伝播であることを確認したため、NeckRange専用の次候補を次で固定する。

- `active_wave_hold = 1.00`。各controlのwave到達前は前substep角を保持し、到達後に既存coupling + Active Driveへ解放する。
- `active_directional_control_step_tip = 0.18rad`。通常の後端/前端保持ではtip上限0.05radを維持し、前方swing中だけdistal側に旧方向へ残る角度自由度を与える。
- `active_preload_contraction = -0.035`へ戻す。伸縮は攻撃勢いの表現として維持するが、cross位相の調整には使用しない。
- `directional_clamp_upstream_blend = 1.00`を維持し、U字抑止を弱めない。
- 採用条件は従来どおり、30/60/120fpsでroot < middle < tip、最大総曲率<=2.20rad、端点ほぼ直線、速度ピーク順序、tip速度優位、伸長量条件を同時に満たすこと。


#### 2026-10-08 Active wave hold後のdistal上限再調整

`active_wave_hold=1.00` と攻撃中distal上限0.18radを有効化しても、30/60fpsのcrossは root/middle/tip = 0.09/0.12/0.12、0.10/0.1167/0.1167のまま変化しなかった。wave hold自体ではなく、hold中のdistal controlが0.18rad clampで上流へ引き戻されている。

次候補は攻撃中だけ `active_directional_control_step_tip=0.24rad` とする。

- 通常のrear/front保持では従来tip上限0.05radを維持する。
- swing中だけdistal側へ0.24radまで旧方向へ残る自由度を与える。
- root 0.32 / middle 0.22 / active tip 0.24 の8 control差上限合計は約2.17radで、総曲率2.20rad契約の設計範囲内に収める。
- `active_wave_hold=1.00`、tip mass=1.90、tip drive=1.75は維持する。
- 採用条件は閾値を変えず、30/60/120fpsすべてでroot < middle < tip、最大総曲率<=2.20rad、端点ほぼ直線、角速度peak順、tip実速度優位、伸長条件を同時に満たすこと。
- この候補でも不成立なら、数値だけの追加追い込みを停止し、Human Verificationで見た目を再評価する。


#### 2026-10-08 distal 0.24rad候補の棄却とHuman Verification復帰

攻撃中distal上限を0.18→0.24radへ広げても、30/60fpsのcross時刻は変化しなかった。

- 30fps: root/middle/tip = 0.09 / 0.12 / 0.12
- 60fps: root/middle/tip = 0.100 / 0.1167 / 0.1167
- 120fpsを含むその他の速度ピーク順序、tip実速度優位、弾性伸長、端点形状、総曲率2.20rad契約には新規failureなし。

したがって0.24rad候補は不採用とし、攻撃中distal上限は0.18radへ戻す。これ以上cross時刻だけを目的にmass / spring / clamp / preloadを数値追い込みしない。

現在の実装では以下が成立している。

- 頭部Head Driveは既存仕様のまま。
- 後端で弾性preloadを持つ。
- Passive Flexに加え、弧長ごとに遅延したActive Driveを持つ。
- 毛先側massとdrive gainを増やし、tipの実描画速度をmiddleより高くする。
- swing後半で弾性伸長し、front hold後に残留伸長へ減衰する。
- root固定、端点ほぼ直線、U字禁止、停止後C字復帰を維持する。

ここからは自動testのcross 1frame差だけを完成判定にせず、MacのNeckRangePreviewで「頭が先行し、アホ毛自身が後方で溜め、根元→中央→毛先へ波が走り、最後に毛先が加速して前方へ伸びる」見た目をHuman Verificationする。見た目が未達なら、その録画を次の設計入力とする。


#### 2026-10-08 Human Verification: 振り抜き慣性で約1.25倍へ一時伸長

Mac Human Verificationで現在のActive Drive / Passive Flexは「だいぶ良くなった」と確認された。次の要望は、前方へ振った勢いによってアホ毛全体が一瞬約1.25倍まで伸びることである。

これは前端保持時の恒常長を1.25倍にする仕様ではない。**振り抜き速度による一時的なovershoot**として扱う。

- 後端保持: 現在どおり少量のpreload contractionを持つ。
- 前方swing前半: まだ縮みを残し、頭部→root→middleの方向転換を優先する。
- swing後半: Active Driveと毛先側慣性が立ち上がるタイミングで伸長を急増させる。
- swing終端〜前端到達直後: centerline全長が基準弧長の約1.25倍を最大値とする。
- 前端保持: 1.25倍を固定せず、最初の約0.10〜0.12秒で急速に約1.02倍まで戻す。
- reset/停止: 伸長0へ戻し、待機C字の基準弧長へ復帰する。
- 根元座標は頭部anchorへ固定し、伸長はsegment lengthだけで表現する。
- 根元直後だけ極端に引き伸ばさず、弧長10〜20%までに伸長率を立ち上げ、その先はほぼ均等に伸びる。これにより「毛先だけびよよーん」ではなく毛束全体が勢いで伸びる。
- width、UV、mesh topologyは維持する。
- これはNeckRangePreview専用Human Verification候補であり、合格まではMotionPreview/Battle共通defaultへ昇格しない。
- 頭部モーション、Active Driveの角度伝播、PARRY、FollowThroughは変更しない。

自動検証は最大centerline ratioを従来1.04〜1.07から**1.22〜1.28**へ更新する。またfront hold終盤では1.04以下まで戻ることを検査し、「1.25倍を保持する」実装を禁止する。


#### 2026-10-08 1.25倍伸長の実測補正

初回候補 `STRIKE_STRETCH=0.30` を実メッシュcenterlineで測定した結果、30/60/120fps・P1/P2・1280/1600の全条件で最大ratioは **1.118448** だった。内部segment伸長値と実描画centerline倍率は1:1ではない。

この実測から、基準長1.0に対する増分を線形近似して次候補を求める。

- 実測: internal +0.30 → centerline +0.118448
- 目標: centerline +0.25
- 次候補: `0.30 * 0.25 / 0.118448 ≈ 0.633`

したがってNeckRangePreview専用の振り抜きpeakを `STRIKE_STRETCH=0.63` とする。入力上限は0.70まで許可するが、通常Battle/MotionPreviewの既定値・挙動は変更しない。

採用条件:
- 実描画centerline最大ratio 1.22〜1.28。
- peakはswing終端〜前端到達直後のみ。
- 前端保持0.12秒後には残留2%相当へ戻る。
- width、root固定、角度chain、U字禁止条件を維持する。


#### 2026-10-08 1.25倍伸長が反映されなかった原因

`STRIKE_STRETCH` を0.30→0.63へ変更しても実描画centerline最大ratioが1.118448から全く変化しなかったため、伸長値の受け渡し経路をread-backした。

原因は `AhogeActionMotion.advance()` の `_advance_softness()` 呼び出し直前に残っていた `clampf(elastic_stretch, -0.08, 0.14)` である。

- NeckRangePreviewは0.30/0.63を生成していた。
- NeckRangeFighterも0.70まで受け取れていた。
- `_advance_softness()` 自体も0.70まで受け取れるよう修正済みだった。
- しかし `advance()` の中間clampだけ0.14のままで、実際の描画には常に最大+0.14しか届いていなかった。
- そのため0.30と0.63の両候補が同じ1.118448倍になった。

修正:
- `advance()` のelastic stretch clamp上限も0.70へ統一する。
- 過剰補正していた `STRIKE_STRETCH=0.63` は不採用とし、元の0.30へ戻す。
- 実測では0.14入力で全長1.118448倍なので、0.30入力では線形近似で約1.254倍となり、目標1.22〜1.28の中央付近になる見込み。
- 伸長分布、0.12秒での急速復帰、根元固定、角度chainは変更しない。


## 次フェーズ: 通常攻撃とパリィのHuman Verification

2026-10-08のMac Human Verificationで、NeckRangePreviewで調整したチャージ攻撃系の基礎モーションは「だいぶ良くなった」、振り抜き時の一時伸長も含めて次工程へ進める状態と判断された。

以後、通常攻撃とパリィも同じ手順で個別にHuman Verificationする。ただしチャージ攻撃の数値を無条件にコピーしない。

### 共通の進め方

1. 実Battleと同じ描画コードを使う `NeckRangePreview.tscn` のモード切り替えで対象動作だけを再生する。
2. まず現在実装の見た目をMac録画で確認する。
3. Human Verificationの指摘を設計正本へ反映する。
4. 未承認の調整値はPreview専用として隔離し、Battle共通defaultへ即時反映しない。
5. 自動試験は見た目の要求を固定するために追加する。
6. CI合格後もHuman VerificationがOKになるまで採用しない。
7. Human Verification合格後にだけ共通Battle値へ昇格する。

### 通常攻撃ゲート

NeckRangePreviewのモード=`通常攻撃`を正本確認経路とする。

確認対象:
- 頭部が先に前へ駆動すること。
- アホ毛が頭部へ剛体追従せず、root→middle→tipへ運動が伝わること。
- チャージ攻撃より短く軽い予備動作であること。
- Active Strikeによりアホ毛自身が相手へ加速すること。
- 毛先が最後に最も速くなること。
- 通常攻撃として必要な一時伸長量・戻り時間はHuman Verificationで決める。チャージ攻撃の約1.25倍を既定値としてコピーしない。
- 接触後FollowThrough、接触freeze、PARRY遷移の既存契約を壊さない。

### パリィゲート

NeckRangePreviewのモード=`パリィ`を正本確認経路とする。

確認対象:
- 頭部の短い切り返しがアホ毛より先行すること。
- 根元側を大きく振り回さず、主に中腹〜毛先で素早く払い返すこと。
- 近距離防御として見え、通常攻撃のように相手頭部へ長く伸び続けないこと。
- prepare→sweep→recoilが1本の柔らかい毛束として連続すること。
- 最初の1frameは直前427 verticesを保持する既存PARRY entry契約を維持すること。
- STRIKE→PARRY、WINDUP→PARRY、IDLE→PARRY等の既存遷移を壊さないこと。
- パリィ固有の伸縮が必要かどうかはHuman Verificationで決める。現時点ではチャージ攻撃の1.25倍伸長をコピーしない。

通常攻撃Human Verificationを先に完了し、その後パリィへ進む。両者を同時に調整して原因を混ぜない。


### 同一画面での3モード切り替え

通常攻撃・チャージ攻撃・パリィのHuman Verificationは別Sceneへ分離せず、現在チャージ攻撃を調整している `NeckRangePreview.tscn` へモード切り替え部品を追加して行う。

モードは次の3つとする。

- チャージ攻撃
- 通常攻撃
- パリィ

共通要件:

- 同じ画面、同じLONG_TEST fighter、同じ承認アホ毛素材・profileを使用する。
- 向き、内部解像度、柔らかさ、手動の首位置確認は共通部品として残す。
- 「動作テスト」ボタンは選択中モードのモーションをループ再生する。
- モード切り替え時は再生を停止し、古いActionMotion状態・方向付き伸長・弾性伸長を次モードへ持ち越さない。
- チャージ攻撃は現在Human Verificationで良好とされたモーションを変更しない。
- 通常攻撃・パリィはこの画面内で独立に調整し、未承認値をBattle共通defaultへ自動昇格しない。
- パリィは既存 `AhogeParryMotion` / PARRY stateの実変形コードを使用し、見た目だけを別の偽物モーションで代替しない。

初期表示はチャージ攻撃とする。通常攻撃・パリィの初期パラメータはHuman Verificationのための出発点であり、ここで完成扱いしない。


### チャージ攻撃Previewの復帰確認区間

Human Verificationで、チャージ攻撃そのものは良好だが、現在の確認画面は攻撃を連続ループするため「攻撃終了後に標準形状へ戻る動作」を確認できないことが指摘された。

NeckRangePreviewのチャージ攻撃モードは、攻撃本体の調整値を変えず、確認周期だけを次のフルサイクルへ変更する。

1. **IDLE開始**: 頭部は基準0D、directional amount=0、elastic stretch=0、待機C字。
2. **CHARGE_PREP**: 基準0Dから後端-0.4Dへ移動しながら、directional amountを0→1、後方targetを立ち上げ、preload contractionへ入る。
3. **REAR_HOLD**: 既存の後端保持0.30秒。現在のチャージ攻撃調整値をそのまま使用する。
4. **STRIKE_SWING**: 既存0.15秒の前方切り返し。頭部・Active Drive・一時伸長は変更しない。
5. **FRONT_HOLD**: 既存0.30秒。振り抜き時の約1.25倍overshoot後、残留伸長へ戻る。
6. **RETURN_TO_IDLE**: 前端+0.4Dから基準0Dへ戻しながらdirectional amountを1→0、elastic stretchを0へ戻す。待機C字へ自然復帰させる。
7. **IDLE_HOLD**: 基準0D・待機C字へ自然減衰し、Human Verificationで復帰途中から復帰完了まで目視できる時間を確保する。

初期候補:
- CHARGE_PREP = 0.20秒
- RETURN_TO_IDLE = 0.30秒
- IDLE_HOLD = 1.20秒

ループ境界はIDLE_HOLD終端→次周期CHARGE_PREP開始とし、前端や後端へ瞬間ジャンプしない。

既存の `attack_preview_*` 関数は、チャージ攻撃本体の詳細自動検証で使用しているため意味を変更しない。UIループ用にフルサイクル関数を追加し、既存の速度・曲率・1.25倍伸長検証を壊さない。


#### 2026-10-08 待機C字への自然復帰時間

初回のIDLE_HOLD=0.45秒では、directional amount=0、elastic stretch=0、Active Drive解除、頭部0Dまでは戻ったが、柔らかいcontrol chainが標準C字へ十分収束しきらず自動検証で不合格になった。

標準形状へ瞬間スナップさせるのではなく、復帰運動そのものをHuman Verificationしたいため、IDLE_HOLDを **1.20秒** へ延長する。

- RETURN_TO_IDLE 0.30秒は維持。
- その後1.20秒、頭部0D・directional amount=0・elastic stretch=0・Active Drive解除のまま自然減衰させる。
- 待機区間終盤でprofile標準C字へ収束していることを自動検証する。
- ループ境界は標準C字→次のCHARGE_PREP開始とし、形状の瞬間ジャンプを作らない。


### 通常攻撃・パリィの間隔追加と初動/復帰の連続化

2026-10-08 Human Verification録画で、通常攻撃・パリィは連続ループが速すぎて各動作の開始前/終了後を確認しにくい。また次の2つの視覚不具合を確認した。

1. 動作開始直後、毛先側だけが一瞬強く曲がり「ひん曲がった」形になる。
2. 動作終了後、待機C字へ戻る境界で形状が一段で切り替わり「がくん」となる。

#### 共通確認周期

チャージ攻撃と同様、通常攻撃・パリィにも開始前と終了後の待機区間を持たせる。

- 開始前IDLE_HOLD: 0.45秒。基準0D・待機C字。
- 動作本体: 各モードの既存/調整対象モーション。
- RETURN_TO_IDLE: 0.35秒。入力・頭部位置・伸縮を基準へ戻す。
- 終了後IDLE_HOLD: 1.20秒。柔軟chainが待機C字へ自然収束するまで確認する。
- ループ境界では終了後IDLE_HOLDから次周期の開始前IDLE_HOLDへ連続し、ActionMotion resetが見える形状ジャンプを作らない。

#### チャージ攻撃・通常攻撃の初動tip折れ

NeckRange専用 `active_tip_mass=1.90` は前方振り抜き時の慣性を作る値であり、後方準備にも常時適用するのは誤り。

- `active_progress <= 0` の後方準備/保持では追加tip massを無効化し、mass=1.0を基準とする。
- 前方swingで `active_progress` が0→約0.35へ進む間にtip massを1.0→1.90へ滑らかに立ち上げる。
- これにより後方準備でmiddleだけ先行してtipが残りすぎる一瞬のhookを抑える。
- forward strike後半のtip inertia / tip drive gain=1.75は維持する。
- 共通Battle defaultのtip mass=1.0は変わらない。

通常攻撃のPREPは現行0.10秒から0.16秒へ延長し、最初0.04秒は頭部だけが先に動き、directional amountは0のまま。その後0.12秒でdirectional amountを0→1へsmoothstepする。待機C字から後方targetへ瞬時に引っ張らない。

#### パリィ初動tip折れ

既存Parryのprepareは、0.18秒全体の最初12%（約0.022秒）で `PREPARE_ANGLE=0.24rad` まで毛先側を曲げており、60fpsでは最初の可視frameでほぼ最大prepareへ到達する。

Human Verification候補:
- PREPARE_ANGLE: 0.24 → 0.10rad。
- prepare区間: u=0.00→0.22。
- sweep到達: u=0.22→0.58。
- recoil: u=0.58→0.82。
- return: u=0.82→1.00。
- SWEEP_ANGLE / RECOIL_ANGLE自体は現段階では変更しない。

これにより最初の1〜2frameでtipだけが急に折れる挙動をなくし、頭部の小さいprepareから払いへ連続させる。

#### 復帰時の「がくん」防止

通常攻撃・パリィとも、動作直後に次周期へresetしない。RETURN_TO_IDLEと1.20秒の終了後IDLE_HOLDで、現在の実形状から待機C字へ自然復帰させる。

- directional amount、elastic stretch、Active DriveはRETURN_TO_IDLE中に連続的に0へ戻す。
- PARRY終了後はActionMotionの既存 `_recover_from_entry()` を0.35秒以上進めてからIDLE_HOLDへ入る。
- ループ境界の `reset_neck_preview_action()` は、既に待機C字へ収束した後にだけ実行されるため、目視できるjumpを作らない。


### 2026-10-08 録画再確認: 通常攻撃のtip hookとループ境界jump

追加録画2本をframe単位で再確認した結果、前回の原因解釈を修正する。

#### 1本目: 通常攻撃初動の毛先hook

対象はパリィではなく通常攻撃。待機C字から頭部が後方へ動き始めた約0.08〜0.14秒の区間で、根元〜中央が左へ倒れ始める一方、毛先側だけ待機C字の右向き曲率が残り、短時間だけhook状に折れている。

原因はPREP中の `_normal_directional_amount()` が、頭部先行0.04秒の後に残り0.12秒で0→1まで上がっていたこと。待機C字から後方直線targetへ途中で強く混ぜるため、上流が先に直線化され、distalのC字だけが残る。

修正:
- `NORMAL_PREP_DIRECTIONAL_MAX = 0.20` を追加。
- PREP中はdirectional amountを0→0.20までに制限し、待機C字を大きく崩さない。
- STRIKEへ入った後、q=0→0.35で0.20→1.00へ滑らかに立ち上げる。
- 頭部の0.04秒先行、通常攻撃のhead ratio、preload量は維持する。
- forward strike中のActive Drive / tip mass / tip driveは維持する。

#### 2本目: 復帰後の1frame jump

標準位置0Dへ戻った後、1frameだけ別のC字へスナップし、次frameで元のC字へ戻る。これは復帰補間ではなく、Previewループ境界で `reset_neck_preview_action()` と `reset_ahoge_soft_follow()` を実行し、ActionMotion/soft chainを作り直していたため。

修正:
- 再生ループ境界ではActionMotion/soft chainをresetしない。
- 終了後IDLE_HOLDで自然収束した内部状態を、そのまま次周期の開始前IDLE_HOLDへ持ち越す。
- resetはモード変更・手動再生開始など、画面上で連続再生していない境界だけに限定する。
- 通常攻撃、チャージ攻撃、パリィの全モードで同じルールとする。

#### パリィ変更の訂正

前回、録画の初動hookをパリィprepareと誤認して `PREPARE_ANGLE=0.10` 等へ変更したが、この2本の録画は通常攻撃を示していた。よってパリィ固有の角度/時間配分は従来値へ戻す。

- PREPARE_ANGLE=0.24
- prepare 0.00→0.12
- sweep 0.12→0.52
- recoil 0.52→0.76
- return 0.76→1.00

パリィの開始前0.45秒・復帰0.35秒・終了後1.20秒の確認間隔は維持する。


### 2026-10-08 directional描画経路の不連続を廃止

追加録画とコードread-backにより、通常攻撃初動のtip hookと復帰時の「がくん」に共通する構造上の原因を確認した。

`AhogeActionMotion._softened_angles()` は現在、`_soft_directional_amount > 0.000001` のときだけ方向付きchainを直接描画し、0以下ではPassive Flexのoffset描画へ切り替える。このためamountが0↔微小値を跨ぐだけで、**補間値ではなく描画アルゴリズム自体が切り替わる**。

この不連続は数値を0.20や0.10へ下げても解消しない。

修正方針:

- Passive Flex結果を常に計算する。
- directional chain結果もsoft controlが有効なら計算する。
- 最終segment角は `lerp_angle(passive_result, directional_chain, directional_amount)` で連続補間する。
- directional_amount=0では従来Passive Flexと完全一致する。
- directional_amount=1では従来directional chainと一致する。
- 0<amount<1では両者の中間となり、0境界で形状が1frame切り替わらない。
- root固定、control数、角度clamp、Active Drive、弾性伸長、PARRY形状は変更しない。

通常攻撃PREPではこの連続補間を前提にdirectional amountを0→0.20まで使用する。復帰では1→0へ下げても同じ連続式のまま待機C字へ戻る。

採用条件:
- amount=0とamount=0.0001の最終形状差が微小であること。
- amount=1は従来directional描画と同等であること。
- 通常攻撃のPREP開始・RETURN終端で1frame形状jumpを生じないこと。
- 既存チャージ攻撃の後方/前方形状・1.25倍伸長を壊さないこと。


#### 復帰開始時のActive Drive切断を廃止

通常攻撃のFRONT_HOLD→RETURN_TO_IDLE境界でも不連続を確認した。従来はFRONT_HOLD終端まで `active_progress=1`、RETURN開始直後から `-1` へ切り替えていた。一方、directional amountはRETURN開始時点ではまだ1に近い。

このため方向付きchainがまだ有効なままActive Driveだけが1frameで消え、復帰開始時のshape/velocity targetが急変する。

修正:

- 通常攻撃はRETURN_TO_IDLE中も `active_progress=1` を保持する。
- Active Driveの見た目の効力は `directional_amount: 1→0` によって滑らかに抜く。
- RETURN完了後、directional amount=0 / elastic stretch=0になったIDLE区間で初めて `active_progress=-1` へ戻す。
- チャージ攻撃も同じ境界規則へ揃える。攻撃本体の値は変更しない。
- これによりFRONT_HOLD→RETURNとRETURN→IDLEの両境界で、目視できるshape jumpを作らない。


## 待機アホ毛形状の再定義: 短い潰れC字

2026-10-08 Human Verificationで、現在の待機アホ毛は長すぎ・縦に大きすぎることを確認した。基準イメージは、頭頂付近へ収まる**短く潰れたC字**であり、現在の約半分の中心線長を目標とする。

現行LONG_TESTの `idle_pose_vertices` 実測:

- centerline arc length: 約1765.20 source px
- centerline bounds width: 約681.53 px
- centerline bounds height: 約968.54 px

初期候補:

- centerline X scale: **0.75**
- centerline Y scale: **0.34**
- 変換後centerline arc length: 約50.5%
- 変換後centerline bounds width: 約75%
- 変換後centerline bounds height: 約34%

この変換は**中心線だけ**へ適用する。断面幅・UV・texture bind・mesh topologyは縮小しない。

実装要件:

- 承認済み `ahoge_straight.png`、`section_left_px/right_px`、bind vertices、UVは変更しない。
- `idle_pose_vertices` を基準にcenterlineだけをroot基準で異方性scaleする。
- 各断面は元の幅を維持し、旧centerline tangent→新centerline tangentの回転だけを適用する。
- 根元vertexはVector2.ZERO固定。
- tipは変換後centerline終点へ移動する。
- straight shape / attack stretchは、新しい短いrest poseから生成する。
- 共通profile scriptのdefault scaleはVector2.ONEとし、LONG_TEST straight profileだけ `Vector2(0.75, 0.34)` を指定する。
- 待機時の中心線長は旧idleの0.48〜0.53倍を自動検証する。
- 高さは旧idleの0.32〜0.36倍を自動検証する。
- 断面幅は旧idleとの差を2%以内に維持する。
- Human Verification合格前はこの待機形状を完成扱いしない。

この変更はモーション数値の微調整より先に行う。通常攻撃・チャージ攻撃・パリィは、短い潰れC字を新しいneutral poseとして再評価する。
