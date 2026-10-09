# Build výstupy musí ležet mimo ~/Documents: iCloud Drive (File Provider) jim přidává
# xattr com.apple.FinderInfo a codesign je pak odmítne („resource fork … not allowed“).
BUILD_ROOT := $(HOME)/Library/Caches/MDView
SPM_BUILD := $(BUILD_ROOT)/spm
SIM_FILE ?= /tmp/mdview-agent.md

.PHONY: test test-core test-watch sim clean

test: test-core

test-core:
	cd Packages/MarkdownCore && swift test --scratch-path "$(SPM_BUILD)"

test-watch:
	cd Packages/MarkdownCore && swift test --scratch-path "$(SPM_BUILD)" --filter FileWatchTests

sim:
	scripts/agent-sim.sh "$(SIM_FILE)" all

clean:
	rm -rf "$(BUILD_ROOT)"
