# ---------------------------------------------------
# ProjectTower の開発・書き出し用のコマンド
#   make dev  … ゲームを起動する（開発中の確認用）
#   make app  … macOS 用のアプリ（build/ProjectTower.app）を書き出す
#   make dmg  … 配布用のディスクイメージ（build/ProjectTower.dmg）を作る（make app も行う）
# Godot の場所は GODOT で変えられる（例: make app GODOT=/Applications/Godot.app/Contents/MacOS/Godot）。
# 書き出しには、Godot と同じ版のエクスポートテンプレートが要る（README の「配布（書き出し）」）。
# ---------------------------------------------------

GODOT ?= godot
NAME := ProjectTower
BUILD := build
APP := $(BUILD)/$(NAME).app
DMG := $(BUILD)/$(NAME).dmg
DMG_STAGE := $(BUILD)/dmg

.PHONY: dev app dmg

dev:
	$(GODOT) --path .

app:
	rm -rf "$(APP)"
	mkdir -p "$(BUILD)"
	$(GODOT) --headless --path . --export-release "macOS" "$(APP)"
	@test -d "$(APP)" || (echo "書き出しに失敗しました（エクスポートテンプレートが入っているか確かめてください）" && exit 1)
	@echo "書き出しました: $(APP)"

# .app と「アプリケーション」フォルダへの近道を入れて、ドラッグで入れられるディスクイメージにする
dmg: app
	rm -rf "$(DMG_STAGE)" "$(DMG)"
	mkdir -p "$(DMG_STAGE)"
	cp -R "$(APP)" "$(DMG_STAGE)/"
	ln -s /Applications "$(DMG_STAGE)/Applications"
	@# 新しい macOS では hdiutil create が非推奨なので diskutil を使う（diskutil image がない古い macOS では hdiutil）
	if diskutil image create from --help >/dev/null 2>&1; then \
		diskutil image create from --format UDZO --volumeName "$(NAME)" "$(DMG_STAGE)" "$(DMG)"; \
	else \
		hdiutil create -volname "$(NAME)" -srcfolder "$(DMG_STAGE)" -ov -format UDZO "$(DMG)"; \
	fi
	rm -rf "$(DMG_STAGE)"
	@echo "作りました: $(DMG)"
