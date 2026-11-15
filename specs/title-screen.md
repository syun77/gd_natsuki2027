# タイトル画面

F5起動は `scenes/title.tscn`。`images/菜月さん/タイトル画面.png` を参考に、黄色の背景・ピンクのガム・左のKAWAII BLASTER!ロゴ・右の菜月さんを使う。メニューは次の2項目のみ。

|表示|動作|
|---|---|
|START|チェックポイント復帰情報を消し、Time Attackを新規開始|
|RELAY再生|リプレイ機能無効化中につき常にグレーアウト、選択不可|

表記はユーザー指定の「RELAY再生」。マウス、標準UIの方向入力と決定（キーボード／ゲームパッド）で選択する。リプレイデータの読み込み・記録・保存は行わない。初期フォーカスはSTART。直接再生シーンを実行してもタイトルへ戻す。

背景原本は `images/title/title_background.png`、同一runtimeコピーは `assets/title/title_background.png`。元参考画像は保持する。背景と操作可能なButtonは別で、メニュー位置や書式はtitle.tscnで編集する。1672×941の共通キャンバスを画面全体を覆う比率で拡縮・中央配置し、標準1280×768では左右をわずかに切り取る。

背景作成はbuilt-in imagegen。最終プロンプト：

> Use case: precise-object-edit. Edit target: the supplied game title screen. Remove ONLY the menu below the KAWAII BLASTER! logo: remove pink START GAME button, its border and pointer, and CONTINUE, OPTIONS, CREDITS, QUIT text. Seamlessly fill that lower-left menu area with the existing yellow background textures. Leave that area empty for runtime menu buttons. Preserve the KAWAII BLASTER! logo, character identity/pose/white dress/blue ponytail/yellow ribbon, pink gum streaks, composition, all other artwork and 16:9 framing unchanged. Do not add any new text or buttons.

検証は `verify_time_attack.gd` の起動・2項目・START・タイトル帰還、`verify_replay.gd` のRELAY再生遷移を使う。

## キャラクター合成用の背景素材

`images/title/title_background_no_character.png` は1672×941の人物なし背景。右の人物、発射点の手、左下の人物透かし、足元の影を除去し、ロゴと黄/ピンクの背景を残す。後で `images/菜月さん/菜月さん3.png` を重ねるための素材で、現行runtime背景とは別に保持する。

built-in imagegenで作成。最終プロンプト：既存背景からすべての人物・手・人物透かし・影を除去し、黄色のグラデーション、網点、斜線、ピンクのガム軌跡で自然に補完する。KAWAII BLASTER!ロゴの文字・位置・サイズ、色調、構図、空のメニュー領域を維持。ビーム終端は手形のない光にする。人物・新規文字・ボタンを追加しない。

## 分離レイヤー素材

`images/title/layers/` の `title_background.png` は黄色背景のみ（1672×941）、`title_effects.png` はピンク/白のビーム・光・軌跡（1672×941、透過RGBA）、`title_logo.png` はKAWAII BLASTER!と周囲の軌道/星（1671×941、透過RGBA）。各画像の左上を同じ位置に置き、背景→エフェクト→ロゴの順で重ねる。ロゴは生成出力が横1px短いため、幅を揃える拡大はせず原寸配置する。現行runtimeへの組込みは別作業。生成再構成であり元画像とのピクセル一致ではない。

built-in imagegen使用。最終プロンプト要旨（個別生成）：背景はロゴ/ピンクの効果を除去し黄色模様で補完。エフェクトはビーム/光/軌跡のみ抽出し黄色背景とロゴを透明化。ロゴは文字/縁/軌道/星のみ抽出して他を透明化。構図・配置・文字を維持し人物や文字を追加しない。
