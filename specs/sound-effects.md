# 効果音

元音源はルートの `sounds/`。checkpoint / crash / dead / door1 / door2 / hit / item / item3 / jump / landing / pull / shoot / vo_checkpoint / vo_1up の14種類の WAV を `natsuki2027/assets/sounds/` にコピーして使用する。

| 音源 | 再生タイミング |
| --- | --- |
| checkpoint | チェックポイントの初回有効化（復帰時は無音） |
| vo_checkpoint（checkpoint_voice） | チェックポイント初回有効化時に既存SEと同時再生。復帰・再通過は無音。DUCKINGバスへ送る |
| crash | ガムで破壊可能ブロックを壊した時（1マスにつき1回） |
| dead | トゲ死亡、落下死亡（手動リスタートは無音） |
| hit | ガムの接着成功。1UPへの命中も含む |
| item3（score_item） | 音符・フランスパンの取得確定時、およびリザルト各項目（区切り線を除く）の表示開始時に1回 |
| vo_1up（one_up_voice） | 1UP獲得確定時に既存item SEと同時に1回再生。接触・ガム回収共通。DUCKINGバスへ送る |
| item | 1UP獲得確定。接触・ガム回収共通 |
| jump | 成功したジャンプ。先行入力は実際に跳ぶ時。拒否・床すり抜けは無音 |
| landing | Player.landed と同じ有効な着地。初期接地は除外 |
| pull | 接着後最初の収縮ステップ、緩めた後の収縮再開。1UP回収も含む |
| shoot | ガム発射成立時。飛行中の無効入力は無音 |

SoundEffects Autoload が非位置依存の AudioStreamPlayer を再生し、終了時に破棄する。各音は一回再生で、同時発音は最大24。死亡音を含む再生中の音はシーン再読込でも維持する。収縮中の X 再入力では pull を重複再生しない。物理挙動と音源の速度・ピッチは変更しない。

検証: `tools/verify_sound_effects.gd` と controls / gum / player / one_up / checkpoint / spike の各検証。

入口・出口のドアは開き始めに door1.wav（door_open）、閉じるアニメーション完了時に door2.wav（door_close）を各1回再生する。入口の待機中と出口の着地・中央への移動中は再生しない。出口は閉扉SEの再生終了を待ってからリザルトを表示する。待機中も閉じたドア・消えたプレイヤーを保持し、ポーズでSEも停止する。

## BGM

メインゲーム開始時に BackgroundMusic Autoload（AudioStreamPlayer）が `assets/bgm/bgm_01.mp3` を再生する。MP3 インポート設定で先頭からループする。全ステージと Time Attack に共通。死亡リスポーンでは再生位置を維持して継続する（チェックポイントの有無によらない）。ポーズ中は一時停止し、タイトルへ戻ると1秒でフェードアウトして停止（タイトル表示は即時）、手動リスタート時は先頭から再生する。リプレイ機能は無効化中で、再生シーンのBGMは開始しない。

リザルト表示開始時にBGMバスのローパス（カットオフ1200Hz）を有効にし、BGMはポーズ中も継続する。タイトルへ戻る際に1秒で線形フェードアウトして停止する。次のゲーム開始時はフェードを取り消し、ローパスを無効にして通常音量で再生する。ダッキング用コンプレッサーは常時有効。

BGMは `BGM` バス、チェックポイント・1UPボイスと死亡SE（dead.wav）は `DUCKING` バス、その他SEは `Master` に送る。`default_bus_layout.tres` のBGMコンプレッサーはDUCKINGをサイドチェインに使用（閾値−24dB、比率8:1、アタック10ms、リリース300ms、ゲイン0dB）。ボイスまたは死亡SEの再生中はBGMを圧縮し、終了後に復帰する。両バスはMasterへ出力し、ボイス自体は圧縮しない。
