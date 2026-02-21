.PHONY: build run test clean install release-patch release-minor release-major

build:
	zig build

run:
	zig build run

test:
	zig build test

clean:
	rm -rf zig-out .zig-cache

install:
	zig build -Doptimize=ReleaseFast
	cp zig-out/bin/cdu /usr/local/bin/cdu

release-patch:
	gh workflow run bump-version.yml -f bump=patch

release-minor:
	gh workflow run bump-version.yml -f bump=minor

release-major:
	gh workflow run bump-version.yml -f bump=major
