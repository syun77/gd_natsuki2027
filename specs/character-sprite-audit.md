# キャラクター画像のサイズ検証

菜月さんの生成元・正規化シート・ゲーム用コピーの仕様。見た目のポーズと物理当たり判定を分離し、プレイヤーには固定カプセルを使用する。通常シートは256pxセル、最近傍フィルタ、ゲーム内の通常描画倍率0.3125。地上の足元下端はy232（排他的）。空中・膝曲げの高さ変化は保持し、ポーズごとに身長を合わせない。

菜月さんの参考画像は `images/菜月さん/`、生成元は `images/` と `images/gum-source/`、ゲーム用シートは `images/normalized/` と `natsuki2027/assets/characters/` に配置する。ガム素材は `specs/character-gum-animations.md` を参照。

## 待機モーション

`images/normalized/natsuki_idle.png` と `natsuki2027/assets/characters/natsuki_idle.png` は帽子姿の菜月さんの同一シート。右向き、待機中は両腕を下ろし帽子を押さえない。白いつば広帽子・濃紺帯、青いポニーテール、白いワンピースと靴。生成元は `images/natsuki_idle_source.png`（1774×887 RGBA）、プロンプトは `specs/natsuki-idle-image-prompt.txt`。

実使用は1024×512 RGBA、256pxセル4列2行、先頭6コマを6fpsでループ。上段4姿勢を共通51.3089% nearest-neighbor縮小し、0/1/2/3/2/1順に配置。alphaは50%閾値で整形。足元は全コマy232（排他的下端）、可視上端36/39/44/51/44/39px、残り2セルは透明。身体の縮尺を個別に合わせず膝曲げの高さ変化を保持。物理形状と再生設定は変更しない。

## 回転ジャンプ用の膝抱えポーズ

`images/natsuki_double_jump.png` は1254×1254 RGBA、帽子姿の菜月さんの右向き単一ポーズ。両膝を胸へ寄せ、右腕で脛を抱え、左手で帽子を軽く押さえる。青いポニーテール、茶色の目、白いつば広帽子と濃紺帯、白いワンピースと靴。透明背景で影・効果・文字なし。

同一PNGを `natsuki2027/assets/characters/natsuki_double_jump.png` に配置し、player.tscnの単一フレーム `double_jump` として使用。AtlasTextureのRect2(315,192,634,870)でalpha128以上の可視領域を参照する。通常倍率0.3125に追加の描画倍率0.19を適用し、切り出し幅相当120.46px／表示約37.64px、切り出し高相当165.3px／表示約51.66px。手元は切り出し中心から(112,195)pxの膝を抱える掌。左右反転・伸縮・中心回転は共通描画処理に従う。回転中は発射姿勢より優先し、接着・着地・ハシゴ・回収ロックで回転解除。物理原点・当たり判定・ジャンプ挙動は変更しない。

組み込みimagegen使用。プロンプトは `specs/natsuki-double-jump-image-prompt.txt`。

## 菜月さんの通常ジャンプ

`images/natsuki_jump_source.png` が生成元、実使用は `images/normalized/natsuki_jump.png` と同一の `natsuki2027/assets/characters/natsuki_jump.png`。右向き8コマ、1024×512／256pxセル4×2。白い帽子を左手で押さえ、右腕はバランスを取り、最終着地では地面に添える。準備・上昇・空中・下降・着地の姿勢を保持する。回転ジャンプとは別素材。

共通55%nearest縮小、alpha50%閾値、全セルX0。各Yオフセット9/16/13/22/19/16/14/14pxで、下端232/224/218/214/218/224/232/232pxに配置。姿勢ごとの身長合わせはしない。組み込みimagegenで生成・縁修正。プロンプトは `specs/natsuki-jump-image-prompt.txt`。再生選択・物理設定は変更しない。

## 菜月さんの走りモーション

`images/natsuki_run_source.png` は1774×887 RGBAの生成元。実使用は `images/normalized/natsuki_run.png` と同一の `natsuki2027/assets/characters/natsuki_run.png`、1024×512、256pxセル4×2・8コマ。手前の右手で白い帽子の側面のつばを押さえ、奥の左腕を振って右へ走る。青い髪・濃紺帯・白いワンピースと靴は菜月さんの既存素材に合わせる。

共通55%nearest縮小、alpha50%閾値、透明RGB黒、全セルX0／Y14/14/20/19/14/14/14/18で配置。下端232/232/232/224/232/232/232/224。身体を個別に伸縮せず、空中期の足浮きを保持。ゲームの再生速度と物理処理は変更しない。組み込みimagegen生成後、左手を帽子のつばへ接触させる修正を実施。生成プロンプトは `specs/natsuki-run-image-prompt.txt`、最新の手前右手への修正は `specs/natsuki-run-near-hand-prompt.txt`。

通常ジャンプは手前腕で帽子を押さえる。1コマ目の自由腕は奥肩を隠して後方へ、2コマ目は3コマ目より少し前方へ拳を出す。2コマ目修正時、他7コマはsource／normalizedともピクセル不変。最新編集プロンプトは `specs/natsuki-jump-second-arm-prompt.txt`。

走り2・6コマ目の奥左腕は4・8コマ目に合わせ前方の曲げ姿勢へ整理。既存55%nearestとY14／下端232を維持し、その他6コマはpixel不変。プロンプトは `specs/natsuki-run-arm-2-6-prompt.txt`。
