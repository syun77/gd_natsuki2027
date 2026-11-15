# 1UPの周回テストシーン

`natsuki2027/scenes/test.tscn` を F6 で実行する。画面中央の菜月さんの周囲を、同じ1UP帽子11個が等間隔に時計回りで周回する。1UPの画像自体は直立を保つ。

菜月さんは承認済み正面を整形した627px静止画（`images/normalized/natsuki.png`／runtime `assets/characters/natsuki.png`）を0.5倍で表示。1UPは32px、最近傍フィルタ。周回半径は230px、速度は毎秒30度（12秒で1周）。ルートの Inspector の `Orbit Radius` / `Orbit Speed Degrees` で変更できる。画面サイズ変更時も中央を維持する。

表示専用のシーンで、物理・取得判定は持たない。
