VERSION ?= dev
COMMIT := $(shell git rev-parse --short HEAD 2>/dev/null || echo "none")
LDFLAGS := -s -w -X main.version=$(VERSION) -X main.commit=$(COMMIT)

.PHONY: build install test lint clean

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
