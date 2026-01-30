include simple/Makefile

lint:
	@echo Lint start
	@golangci-lint run -v ./...

test:
	@echo Test start
	@go list -f '{{if gt (len .TestGoFiles) 0}}"go test -tags test -covermode count -coverprofile {{.Name}}.coverprofile -coverpkg ./... {{.ImportPath}}"{{end}}' ./... | xargs -I {} sh -c {}
	@gocovmerge `ls *.coverprofile` | grep -v ".pb.go" > coverage.out
	@go tool cover -func coverage.out | grep total

cover: test
	@go tool cover -html coverage.out

clean:
	@rm -f *.coverprofile
	@rm -f coverage.*
	@echo Clean Finish

download:
	@php php/bili/main.php

.PHONY: lint test cover clean
