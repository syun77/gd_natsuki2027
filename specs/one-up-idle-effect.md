# 1UPの取得可能エフェクト

取得待ちの全1UPに、淡い金色・クリーム色の四芒星を表示する。1UPの外側4か所で時間をずらして開閉し、同時に1〜2個だけ見える。最大7px、白い芯は最大付近の一瞬だけ。1UPを覆う光や輪は使わない。

PixelFX編集元は `images/effects/one-up-idle.mjs`。`tools/build_one_up_idle_effect.mjs` をNode.jsで実行して、原本とGodot用の `one_up_idle.png` を同時に再生成する。96×96pxセル、10列6行、60フレーム、30fps、2秒ループ、中心(48,48)、透過PNG。32pxの1UPと同じ中心にNearestで表示する。

`one_up_collectible.gd` が `one_up_idle_effect.gd` の子Sprite2Dを作成する。配置座標から再生位相を決め、アイテム同士の同期を避ける。`being_pulled` 更新時に即座に隠し、キャンセル時は再表示。取得時も即座に隠し、既存の獲得エフェクトへつなぐ。1UPの削除・ステージ再生成で子も削除される。物理、取得判定、報酬は変更しない。

検証は `tools/verify_one_up_collect_effect.gd`（ループ、引き寄せとキャンセル、取得時の表示、獲得演出の独立寿命）と `verify_one_up_collectibles.gd`、`verify_one_up_reel.gd`。
