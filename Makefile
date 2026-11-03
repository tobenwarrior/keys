APP := .build/keys.app

.PHONY: all test clean run

UNAME_S := $(shell uname -s)

ifeq ($(UNAME_S),Darwin)
all:
	swift build -c release
	rm -rf "$(APP)"
	mkdir -p "$(APP)/Contents/MacOS" "$(APP)/Contents/Resources"
	cp "$$(swift build -c release --show-bin-path)/keys" "$(APP)/Contents/MacOS/keys"
	cp packaging/Info.plist "$(APP)/Contents/Info.plist"
	cp packaging/keys.icns "$(APP)/Contents/Resources/keys.icns"
	cp -R packs "$(APP)/Contents/Resources/packs"
	codesign --force --sign - "$(APP)"
	@echo "Built $(APP)"

run: all
	open "$(APP)"
else
all:
	@echo "keys.app is built on macOS. From the repo root, run: make"
	@echo "On this machine you can run: make test"
	@exit 1
endif

test:
	swift test

clean:
	swift package clean || true
	rm -rf "$(APP)" .build
