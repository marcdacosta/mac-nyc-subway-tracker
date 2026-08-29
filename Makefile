.PHONY: app build run test

build:
	swift build

test:
	swift test

app:
	./Scripts/build-app.sh

run: app
	open ".build/Mac NYC Subway Tracker.app"
