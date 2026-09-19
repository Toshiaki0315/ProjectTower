# ProjectTower - Tech Stack

## 開発環境（決定）
候補だった「Godot Engine」と「TypeScript (Webスタック)」のうち、**Godot Engine 4** を採用しました。

| 項目 | 内容 |
|---|---|
| ゲームエンジン | Godot Engine 4.7（4.7.2 で動作確認） |
| 言語 | GDScript |
| レンダラー | GL Compatibility（`project.godot` の `renderer/rendering_method`） |
| バージョン管理 | Git / GitHub |

### Godot を選んだ理由
- 2Dに特化した軽量なオープンソースのゲームエンジンで、ビルの断面図（タイルのマス目）を扱いやすい。
- シーンやスクリプトがテキストで管理でき、AIコーディングと相性が良い。
- コマンドライン（`godot --path .`、`godot -s <スクリプト>`）から起動・テストでき、AIが自分で動作を確かめられる。

## 実装の方針

### コードファースト
- エディタでのGUI操作（ノード配置）を最小限にし、UI（バー・ボタン・建設メニュー・スクロールバーなど）は `scripts/main.gd` の `create_ui()` でGDScriptから動的に作る。
- エディタで作ったものは `scenes/main.tscn`（`TileMapLayer` と `Camera2D`）だけ。
- 仕組みごとにスクリプトを分け、`scripts/main.gd` がノードとして生成してつなぐ。スクリプトは役割ごとのフォルダに置く（`scripts/systems/` … ゲームの仕組み、`scripts/actors/` … 人・カゴ、`scripts/view/` … 見た目と操作）。

### 建物とマップ
- 建物は `TileMapLayer` のタイルで描く。1マス = 16×16ドット。
- 建物の種類・建設費・横幅・建てられる階は `scripts/main.gd` の `BUILDINGS` にまとめて定義する。横に複数マスの建物は、左端のマスを基準にしたユニットとして扱う。
- 「どこに何があるか」は、描画とは別に `building_grid`（マス → 建物の種類と左端のマス）で管理し、住人の経路探索や各仕組みはこれを参照する。

### 見た目（ドット絵）
- 画像ファイルは使わず、`scripts/view/pixel_art.gd` に建物のドット絵を「1文字 = 1ドット」の文字で描き、起動時に画像（`ImageTexture`）にしてタイルにする。
- 人・エレベーターのカゴ・空・太陽と月・夜の明かりは、`_draw()` でコードから描く。

### 移動と経路探索
- 住人の移動ルール（歩く・階段・エレベーター）は `scripts/main.gd` の `get_moves()` にまとめ、各移動にコスト（手間）を持たせる。
- 経路はダイクストラ法（`find_path()`）で、コストが一番小さいものを選ぶ。
- エレベーターは集合制御（進行方向を保って途中の階に寄る）と、複数のカゴの群管理（到着までの手間の見積もりが一番小さいカゴに割り当てる）。

## テスト
- `tests/screenshot_test.gd`（`SceneTree` を継承したスクリプト）で、ゲームを起動して実際のクリック操作を `push_input` で再現し、結果を確かめてスクリーンショットを保存する。
- 実行: `godot --path . -s res://tests/screenshot_test.gd -- <保存先>`（ウィンドウ付き。約4〜5分）
- 本物のマウスの割り込みやウィンドウが隠れたときの停止を避けるため、テスト中はマウスを受け付けず（`mouse_passthrough`）、垂直同期を切って60fpsに制限する。

## ドキュメント用の画像
- `tools/generate_readme_images.gd` で、README.md に載せる建物・人のドット絵やゲーム画面を `docs/images/` に作る。
- `docs/` には `.gdignore` を置き、Godot がこれらの画像をプロジェクトの素材として取り込まないようにしている。
