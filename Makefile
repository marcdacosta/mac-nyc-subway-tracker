.PHONY: app build release run test

build:
	swift build

test:
	swift test

app:
	./Scripts/build-app.sh

release: test
	./Scripts/package-release.sh

run: app
	open ".build/Mac NYC Subway Tracker.app"
