VERSION:=$(shell date +"%s")
deploy_window: deploy_window_do print_version

deploy_window_do:
	@GOOS=windows GOARCH=amd64 CGO_ENABLED=0 go build -o ~/Downloads/AnonTokyoSiriusServer.exe -v -x -gcflags "-N -l" ./cmd/server_app/main.go
	@zip -r ~/Downloads/AnonTokyoSiriusServerCbor.zip  mastercbor
	@echo deploy AnonTokyoSiriusServer: $(shell curl -s http://10.27.6.27/deploy\?execName\=AnonTokyoSiriusServer.exe\&version\=$(VERSION))
	@echo deploy AnonTokyoSiriusServerCbor: $(shell curl -s http://10.27.6.27/deploy\?execName\=AnonTokyoSiriusServerCbor.zip\&version\=$(VERSION))
	@cp -f ~/Workdata/sirius_server_api/src/Makefile ~/Workdata/testgo/resources/SiriusMakefile

convert_master: convert_master_do print_version

convert_master_do:
	@go run cmd/local_convert_master/main.go

print_version:
	@cat mastercbor/Version;echo
	@echo getLocalTestVersion: $(shell grpcurl -plaintext 10.27.6.27:8080 app.masterdata.MasterdataService.Version|jq -c)
	@echo getTestVersion: $(shell grpcurl l4-dev-all-gs-sirius.bilibiligame.net:443 app.player.PlayerService.Register|jq -c)

proto:
# 	@buf generate
# 	@protofmt -w pb/app/bilibili/anontokyo/*.proto
	@cp Makefile ~/Workdata/testgo/resources

buildCover:
	@GOOS=windows GOARCH=amd64 CGO_ENABLED=0 go build -o ~/Downloads/AnontokyoSiriusBuildCbor.exe -v -x -gcflags "-N -l" cmd/convert_master/main.go
	@curl http://10.27.6.27/deploy\?execName\=AnontokyoSiriusBuildCbor.exe\&version\=$(VERSION)

.PHONY: convert_master proto deploy_window