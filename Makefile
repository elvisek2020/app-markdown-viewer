# Build výstupy musí ležet mimo ~/Documents: iCloud Drive (File Provider) jim přidává
# xattr com.apple.FinderInfo a codesign je pak odmítne („resource fork … not allowed“).
BUILD_ROOT := $(HOME)/Library/Caches/MDView
SPM_BUILD := $(BUILD_ROOT)/spm
DERIVED := $(BUILD_ROOT)/DerivedData
APP_DEBUG := $(DERIVED)/Build/Products/Debug/MDView.app
APP_RELEASE := $(DERIVED)/Build/Products/Release/MDView.app
INSTALL_DIR ?= /Applications
BIN_DIR ?= /opt/homebrew/bin
SIM_FILE ?= /tmp/mdview-agent.md
LSREGISTER := /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
XCODEBUILD = xcodebuild -project MDView.xcodeproj -scheme MDView -derivedDataPath "$(DERIVED)" \
	-destination 'platform=macOS,arch=arm64' -quiet

.PHONY: gen build release run install uninstall test test-core test-watch sim vendor clean

gen:
	xcodegen generate --quiet

build: gen
	$(XCODEBUILD) -configuration Debug build

release: gen
	$(XCODEBUILD) -configuration Release build

run: build
	open "$(APP_DEBUG)"

install: release
	@if [ -d "$(INSTALL_DIR)/MDView.app" ]; then \
		/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$(INSTALL_DIR)/MDView.app/Contents/Info.plist" | grep -qx cz.elvisek.mdview \
			|| { echo "$(INSTALL_DIR)/MDView.app není MDView od cz.elvisek – nepřepisuji"; exit 1; }; \
		rm -rf "$(INSTALL_DIR)/MDView.app"; \
	fi
	ditto "$(APP_RELEASE)" "$(INSTALL_DIR)/MDView.app"
	ln -sf "$(INSTALL_DIR)/MDView.app/Contents/Resources/bin/mdv" "$(BIN_DIR)/mdv"
	$(LSREGISTER) -f "$(INSTALL_DIR)/MDView.app"
	@echo "Nainstalováno: $(INSTALL_DIR)/MDView.app, CLI: $(BIN_DIR)/mdv"

uninstall:
	rm -f "$(BIN_DIR)/mdv"
	rm -rf "$(INSTALL_DIR)/MDView.app"

test: test-core

test-core:
	cd Packages/MarkdownCore && swift test --scratch-path "$(SPM_BUILD)"

test-watch:
	cd Packages/MarkdownCore && swift test --scratch-path "$(SPM_BUILD)" --filter FileWatchTests

sim:
	scripts/agent-sim.sh "$(SIM_FILE)" all

vendor:
	web-vendor/update.sh

clean:
	rm -rf "$(BUILD_ROOT)" MDView.xcodeproj
