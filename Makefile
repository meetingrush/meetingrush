# Optional, untracked overrides such as CODESIGN_IDENTITY.
-include local.mk
export BUNDLE_ID CODESIGN_IDENTITY RELEASE

APP := dist/MeetingRush.app
INSTALL_DIR ?= $(HOME)/Applications

.PHONY: app run install test clean icons release

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

# Regenerates the committed icon files from their SVG sources; needs librsvg (brew install librsvg).
icons:
	rsvg-convert -f pdf Resources/Icons/MenuBarIcon.svg -o Resources/Icons/MenuBarIcon.pdf
	scripts/make-app-icon.sh

# Each run does the next release step; see docs/RELEASING.md.
release:
	@test -n "$(VERSION)" || { echo "Usage: make release VERSION=X.Y.Z" >&2; exit 1; }
	scripts/release.sh "$(VERSION)"

clean:
	rm -rf .build dist
