.PHONY: app build run test

build:
	swift build

test:
	swift test

app:
	./Scripts/build-app.sh

run: app
	open ".build/NYC Subway.app"
