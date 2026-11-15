# 死亡時の煙と帽子落下演出

トゲ接触時に身体とガムを即座に非表示にし、身体の位置へ煙を広げ、白いつば広帽子・濃紺リボンを残す。接続・残像・着地煙を消し、プレイヤー移動を停止する。

- 原画: `images/samples/natsuki_death_hat/hat_source.png`。nearestで透過余白を切り詰め幅72pxへ正規化した `images/effects/player_death_hat.png` と同一runtimeコピー `assets/effects/player_death_hat.png` を使用。表示倍率0.6で、帽子の不透明部分の横幅は約35px。待機中の帽子（約110px×0.3125≒34px）に合わせる。
- `scripts/player_death_effect.gd` はGameの固定stepで更新。接触時の体中心から32px上を帽子中心とする。カメラは接触位置に固定。
- 承認済みサンプルと同じ実時間の動き: 最初0.32秒で12px浮き、周期1.25秒/最大左右42px/傾き24度。落下の進行時間は実時間の0.25倍。表示専用で当たり判定や物理への力はない。
- 死亡から復帰までは0.6秒。長尺サンプルを早送りせず、その時点の帽子をシーンとともに破棄する。最後の残機なら同じ0.6秒後にGAME OVER。奈落死は即時復帰/終了、Rも即時のまま。
- 取得済みアイテム、残機、計時の扱いは `one-up-and-lives.md` / `checkpoints.md` に従う。
- `tools/verify_spikes.gd` で高速接触・単発生成・帽子画像・頭位置・浮き・1/4落下・横揺れ・0.6秒復帰・死亡中の移動停止を確認。lives / replay / pauseの回帰も併用。

## PixelFX消滅煙

`images/effects/player-death-smoke.mjs` が編集元。白/淡い灰紫の密な縦煙が身体を包み、膨らみ、個別の煙玉に分かれて上昇・縮小・透過する。爆発の光や星は付けない。PixelFX `spawn/poof` の立体的な煙の重ね方を参考に制作。帰属は `images/effects/pixelfx-LICENSE.txt` / `pixelfx-NOTICE.md`。

- `player_death_smoke.png`: 96×96pxセル、5列×4行、19コマ（最後は透明）、30fps/0.6秒、pivot48/48、nearest。rootとruntimeの画像は同一。
- 生成: `node images/effects/export-player-death-smoke.mjs`。同フォルダへPNG/JSON/contact sheetを保存しruntimeコピーも更新。shellでNodeを利用できない場合はconnected Nodeからこのexporterをimportする。
- 煙は死亡effectの子Sprite2D、top_levelで接触時の体中心に固定、Z7。帽子はZ8。帽子の移動・回転・0.6倍scaleを煙へ伝えない。Gameの同じstepで煙コマを進め、シーン再生成/ゲームオーバーでまとめて破棄する。物理/残機/復帰時間は変更しない。
- `verify_spikes.gd` は初期コマ/体中心/描画順/帽子と独立したtransform/中間コマ9/最終透明コマ18/再開後の破棄も確認する。
