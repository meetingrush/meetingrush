# Optional, untracked overrides such as CODESIGN_IDENTITY.
-include local.mk
export BUNDLE_ID CODESIGN_IDENTITY SWIFT_BUILD_FLAGS

APP := dist/MeetingRush.app
INSTALL_DIR ?= $(HOME)/Applications

.PHONY: app run install test clean

app:
	scripts/bundle.sh

run: app
	-pkill -x MeetingRush
	open $(APP)

install: app
	mkdir -p "$(INSTALL_DIR)"
	rm -rf "$(INSTALL_DIR)/MeetingRush.app"
	cp -R $(APP) "$(INSTALL_DIR)/"

test:
	swift test

clean:
	rm -rf .build dist
