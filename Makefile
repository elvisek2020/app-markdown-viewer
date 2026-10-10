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
RELEASE_DIR := $(BUILD_ROOT)/release
RELEASE_ZIP := $(RELEASE_DIR)/MDView.zip
RELEASE_DMG := $(RELEASE_DIR)/MDView.dmg
# Verze = čas buildu ve formátu RRRRMMDD.HHMM (stejně jako ostatní projekty). Jde do
# CFBundleShortVersionString i CFBundleVersion aplikace a rozšíření; roste s každým buildem,
# takže si Dock a Finder obnoví ikonu i další údaje z cache.
VERSION := $(shell date +%Y%m%d.%H%M)
XCODEBUILD = xcodebuild -project MDView.xcodeproj -scheme MDView -derivedDataPath "$(DERIVED)" \
	-destination 'platform=macOS,arch=arm64' -quiet MARKETING_VERSION=$(VERSION) CURRENT_PROJECT_VERSION=$(VERSION)

QL_APPEX := Contents/PlugIns/MDViewQuickLook.appex

.PHONY: gen build release run install package publish uninstall unregister-dev ql-status test test-core test-watch sim vendor clean

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
	touch "$(INSTALL_DIR)/MDView.app"
	ln -sf "$(INSTALL_DIR)/MDView.app/Contents/Resources/bin/mdv" "$(BIN_DIR)/mdv"
	@$(MAKE) --no-print-directory unregister-dev
	$(LSREGISTER) -f "$(INSTALL_DIR)/MDView.app"
	pluginkit -a "$(INSTALL_DIR)/MDView.app/$(QL_APPEX)"
	pluginkit -e use -i cz.elvisek.mdview.quicklook
	@qlmanage -r >/dev/null 2>&1; qlmanage -r cache >/dev/null 2>&1
	@echo "Nainstalováno: $(INSTALL_DIR)/MDView.app (verze $$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$(INSTALL_DIR)/MDView.app/Contents/Info.plist")), CLI: $(BIN_DIR)/mdv"
	@# Vzor ukotvený na začátek – jinak by pgrep -f našel i tento shell (cesta je v jeho příkazu).
	@if pgrep -qf "^$(INSTALL_DIR)/MDView.app/Contents/MacOS/MDView"; then \
		echo "Pozor: MDView běží ze staré verze – ukonči ho (⌘Q) a spusť znovu."; \
	fi

# Balíčky pro instalaci bez buildu (GitHub Releases): MDView.dmg ke stažení (přetažení do Aplikací)
# a MDView.zip pro install.sh. Názvy assetů jsou vždy stejné – odkazy releases/latest/download/…
# pak ukazují na poslední verzi.
package: release
	rm -rf "$(RELEASE_DIR)" && mkdir -p "$(RELEASE_DIR)"
	codesign --verify --deep --strict "$(APP_RELEASE)"
	@codesign -dv "$(APP_RELEASE)" 2>&1 | grep -q '^TeamIdentifier=[A-Z0-9]' \
		|| echo "Pozor: ad-hoc podpis (chybí Config/Local.xcconfig) – macOS bude po každé verzi znovu žádat o oprávnění."
	ditto -c -k --sequesterRsrc --keepParent "$(APP_RELEASE)" "$(RELEASE_ZIP)"
	scripts/make-dmg.sh "$(APP_RELEASE)" "$(RELEASE_DMG)"
	@$(MAKE) --no-print-directory unregister-dev
	@echo "Balíčky (verze $(VERSION)): $(RELEASE_DMG) ($$(du -h "$(RELEASE_DMG)" | cut -f1)), $(RELEASE_ZIP) ($$(du -h "$(RELEASE_ZIP)" | cut -f1))"

# Vydání na GitHubu: tag v<verze> na pushnutém commitu, assety MDView.dmg a MDView.zip.
publish: package
	scripts/publish.sh "$(VERSION)" "$(RELEASE_DMG)" "$(RELEASE_ZIP)"

# Buildy v DerivedData (Debug pro self-testy, Release před instalací) se při spuštění registrují
# u LaunchServices – jejich Quick Look rozšíření by soupeřilo s nainstalovaným.
unregister-dev:
	-@$(LSREGISTER) -u "$(APP_DEBUG)" "$(APP_RELEASE)" 2>/dev/null
	-@pluginkit -r "$(APP_DEBUG)/$(QL_APPEX)" 2>/dev/null
	-@pluginkit -r "$(APP_RELEASE)/$(QL_APPEX)" 2>/dev/null

ql-status:
	pluginkit -mAvvv -i cz.elvisek.mdview.quicklook

uninstall:
	-pluginkit -r "$(INSTALL_DIR)/MDView.app/$(QL_APPEX)" 2>/dev/null
	-$(LSREGISTER) -u "$(INSTALL_DIR)/MDView.app" 2>/dev/null
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
