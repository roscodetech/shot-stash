APP = build/ShotStash.app
DEST = /Applications/ShotStash.app

.PHONY: build bundle install test clean run

build:
	swift build -c release

bundle: build
	./scripts/bundle.sh

install: bundle
	@pkill -x ShotStash 2>/dev/null || true
	rm -rf "$(DEST)"
	cp -R "$(APP)" "$(DEST)"
	open "$(DEST)"
	@echo "Installed to $(DEST)"

test:
	swift test

run:
	swift run ShotStash

clean:
	rm -rf .build build
