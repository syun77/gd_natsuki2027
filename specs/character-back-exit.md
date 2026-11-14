# 背面退場画像

真後ろ向きの帽子姿の菜月さん。右手で帽子を軽く押さえ、帽子リボンとポニーテールはキャラクター左側。腰は帯のみ。青い髪・白いつば広帽子と濃紺帯・白いワンピースと靴を共通使用する。

生成元は `images/natsuki_back_exit_source.png`（1024×1536 RGBA）。`tools/build_character_door_art.py`でalpha128を抽出し、共通高さ196px・足元y232の256pxセルへnearest整形。`images/normalized/natsuki_back_exit.png` と `natsuki2027/assets/characters/natsuki_back_exit.png` は同一PNGでゲーム反映済み。ドアの演出や移動の物理は変更しない。

組み込みimagegenで制作。プロンプトは `specs/natsuki-exit-image-prompt.txt`。外見の正本は `specs/natsuki-character-design.md`。
