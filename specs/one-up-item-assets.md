# 1UPアイテム素材と配置

`images/items/one_up_hat.png` とGodot用 `assets/items/one_up_hat.png` は32×32 RGBAの同一画像。試作 `images/items/one_up_hat_trial_source.png` の可視領域をNearestで30px以内に収め、透明余白付き32pxへ正規化した。白い夏帽子・紺帯・黄色リボンと1UP文字。Sprite2Dのみ2倍にし、最近傍で64×64px表示する。配置中心と半径36pxの取得・ガム命中判定は維持する。

ステージの `Foods` TileMapLayerと配置セル・source0/alternative0〜10はマップ/エディタの現行データ契約として保持する。全11IDとも `scenes/items/one_up.tscn` を生成する。同じシーンを使うため、どのIDでペイントしても効果は同じ。専用TileSetは `assets/items/one_up_tileset.tres`。MapEditではカテゴリ/候補とも「1UP」。既存編集セッションのセルもそのまま取り込める。検証マップは36配置。生成原本は `stage_layout.gd` の `ONE_UPS`。手編集マップを生成器で上書きしない。

Area2Dはbit32、プレイヤーbit2を監視し、接触またはガム手元到達で一度だけ回収する。判定は現行配置の操作感を保つ半径36px。地形・箱とは衝突しない。残機を1増加し、得点は加算しない。「1UP」だけを既存popupテーマで0.65秒・32px上昇表示する。取得音と獲得粒子を再生し、待機きらめきは消す。

Gameのcollection_allowedで死亡/ゲームオーバー/クリア/退出確定後の取得を止める。配置時のparent pathとlocal positionで取得を識別し、ガム移動後も死亡復帰で再生成しない。手動retry/new gameでは再配置する。

[残機制](one-up-and-lives.md)、[ガム回収](one-up-gum-reel.md)、[取得演出](one-up-collect-effect.md)、[待機演出](one-up-idle-effect.md)を参照。制作資料の料理原画は `images/foods/` に保管し、runtimeには含めない。

検証: `tools/verify_one_up_collectibles.gd`、`verify_one_up_reel.gd`、`verify_lives.gd`、`verify_mapedit.gd`（最後は--editor付き）。
