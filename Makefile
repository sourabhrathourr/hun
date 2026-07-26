VERSION ?= $(shell git describe --tags --always --dirty 2>/dev/null || echo "dev")
COMMIT := $(shell git rev-parse --short HEAD 2>/dev/null || echo "none")
LDFLAGS := -s -w -X main.version=$(VERSION) -X main.commit=$(COMMIT)
RELEASE_VERSION ?=
RELEASE_BUILD ?=

.PHONY: build install test lint clean dev-macos package-macos-release release release-dry-run

build:
	go build -ldflags "$(LDFLAGS)" -o hun ./cmd/hun

install:
	go install -ldflags "$(LDFLAGS)" ./cmd/hun

test:
	go test ./... -v -count=1

lint:
	golangci-lint run ./...

clean:
	rm -f hun

dev-macos:
	./scripts/dev-macos.sh

package-macos-release:
	./scripts/package-macos-release.sh \
		--version "$(RELEASE_VERSION)" \
		--build "$(RELEASE_BUILD)" \
		--notary-profile hun-notary \
		--generate-appcast

release:
	./scripts/release.sh

release-dry-run:
	./scripts/release.sh --dry-run
