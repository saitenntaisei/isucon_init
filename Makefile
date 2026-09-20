SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c
.DEFAULT_GOAL := help
.NOTPARALLEL:

ENV_FILE ?= env.sh
-include $(ENV_FILE)

# env.sh / export / make の引数で指定した値を優先する。
SERVER_ID ?=
APP_USER ?= isucon
BIN_NAME ?= isucondition
BUILD_DIR ?= /home/isucon/webapp/go
SERVICE_NAME ?= $(BIN_NAME).go.service
DB_SERVICE ?= mysql
NGINX_SERVICE ?= nginx
MYSQL_OS_USER ?= mysql
MYSQL_OS_GROUP ?= $(MYSQL_OS_USER)

DB_PATH ?= /etc/mysql
NGINX_PATH ?= /etc/nginx
NGINX_CONFIG ?= $(NGINX_PATH)/nginx.conf
NGINX_ACCESS_CONFIG ?= $(NGINX_CONFIG)
SYSTEMD_PATH ?= /etc/systemd/system
APP_ENV ?= $(HOME)/env.sh
NGINX_LOG ?= /var/log/nginx/access.log
DB_SLOW_LOG ?= /var/log/mysql/mariadb-slow.log
LOG_DIR ?= ./$(SERVER_ID)/logs
REPORT_DIR ?= ./local/reports

MYSQL_HOST ?= 127.0.0.1
MYSQL_PORT ?= 3306
MYSQL_USER ?= isucon
MYSQL_PASS ?=
MYSQL_DBNAME ?= isucondition
ALP_VERSION ?= 1.0.9
ALP_ARCH ?= amd64
TBLS_VERSION ?= 1.71.1
GIT_USER_NAME ?= server
GIT_USER_EMAIL ?= github-actions[bot]@users.noreply.github.com
WEBHOOK_URL ?=
NETDATA_WEBROOT_PATH ?= /var/lib/netdata/www/
NETDATA_CUSTOM_HTML ?= ./tool-config/netdata/*

.PHONY: help init-env check backup
help:
	@printf '%s\n' \
		'make init-env   設定例から env.sh を作る（既存ファイルは保持）' \
		'make check      設定とアプリの配置先を確認' \
		'make setup      バックアップ・ツール導入・Git/nginx 設定' \
		'make get-conf   現在のサーバー設定を取得' \
		'make bench      ビルド・ログ退避・再起動・計測準備' \
		'make analyze    生ログと集計結果を保存' \
		'make slow-off   スロークエリ記録を停止'

init-env:
	@if [ -e "$(ENV_FILE)" ] || [ -L "$(ENV_FILE)" ]; then \
		printf '%s already exists\n' "$(ENV_FILE)"; \
	else \
		umask 077; cp env.sh.example "$(ENV_FILE)"; \
		printf 'Edit %s before make setup\n' "$(ENV_FILE)"; \
	fi

check: check-server-id
	@test -d "$(BUILD_DIR)"
	@printf '%s\n' 'SERVER_ID=$(SERVER_ID)' 'BUILD_DIR=$(BUILD_DIR)' \
		'SERVICE_NAME=$(SERVICE_NAME)' 'DB_SERVICE=$(DB_SERVICE)' \
		'NGINX_ACCESS_CONFIG=$(NGINX_ACCESS_CONFIG)'

backup: check
	@mkdir -p local
	@backup=$$(mktemp -d "local/start-$(SERVER_ID)-XXXXXXXX"); \
		paths=("$(DB_PATH)" "$(NGINX_PATH)" "$(SYSTEMD_PATH)/$(SERVICE_NAME)" "$(BUILD_DIR)"); \
		if [ -f "$(APP_ENV)" ]; then paths+=("$(APP_ENV)"); fi; \
		if [ -f "$(ENV_FILE)" ]; then paths+=("$(ENV_FILE)"); fi; \
		sudo tar -czf "$$backup/original.tar.gz" "$${paths[@]}"; \
		sudo chmod 600 "$$backup/original.tar.gz"; \
		printf 'Backup: %s\n' "$$backup"

# メインで使うコマンド ------------------------

# サーバーの環境構築　ツールのインストール、gitまわりのセットアップ
.PHONY: setup
setup: backup install-tools git-setup set-nginx-alp-ltsv

# 設定ファイルなどを取得してgit管理下に配置する
.PHONY: get-conf
get-conf: check-server-id get-db-conf get-nginx-conf get-service-file get-envsh

# リポジトリ内の設定ファイルをそれぞれ配置する
.PHONY: deploy-conf
deploy-conf: check-server-id deploy-db-conf deploy-nginx-conf deploy-service-file deploy-envsh

# ベンチマークを走らせる直前に実行する
.PHONY: bench
bench: check build slow-off mv-logs restart-app slow-on

# slow queryを確認する
.PHONY: slow-query
slow-query:
	sudo mysqldumpslow -s t -t 10 "$(DB_SLOW_LOG)"
	sudo pt-query-digest "$(DB_SLOW_LOG)"

# alpでアクセスログを確認する
.PHONY: alp
alp:
	sudo alp ltsv --file="$(NGINX_LOG)" --config=./tool-config/alp/config.yaml

# fgprofで記録する
.PHONY: fgprof-record
fgprof-record:
	mkdir -p "$(REPORT_DIR)"
	go tool pprof -top http://localhost:6060/debug/fgprof?seconds=60 > "$(REPORT_DIR)/fgprof.txt"
	@if [ -n "$(WEBHOOK_URL)" ]; then curl -fsS -X POST -F "txt=@$(REPORT_DIR)/fgprof.txt" "$(WEBHOOK_URL)" -o /dev/null; fi

# pprofで記録する
.PHONY: pprof-record
pprof-record:
	mkdir -p "$(REPORT_DIR)"
	go tool pprof -top http://localhost:6060/debug/pprof/profile?seconds=60 > "$(REPORT_DIR)/pprof.txt"
	@if [ -n "$(WEBHOOK_URL)" ]; then curl -fsS -X POST -F "txt=@$(REPORT_DIR)/pprof.txt" "$(WEBHOOK_URL)" -o /dev/null; fi

# pprof or fgprofで確認する
.PHONY: go-check
go-check:
	$(eval latest := $(shell ls -rt pprof/ | tail -n 1))
	go tool pprof -http=localhost:8090 pprof/$(latest)

.PHONY: analyze
analyze: check-server-id
	@mkdir -p "$(LOG_DIR)"
	@report=$$(mktemp -d "$(LOG_DIR)/analysis-XXXXXXXX"); \
		sudo cp -p "$(NGINX_LOG)" "$$report/nginx.log"; \
		sudo cp -p "$(DB_SLOW_LOG)" "$$report/mysql.log"; \
		sudo alp ltsv --file="$$report/nginx.log" --config=./tool-config/alp/config.yaml > "$$report/alp.txt"; \
		sudo mysqldumpslow -s t -t 10 "$$report/mysql.log" > "$$report/mysqldumpslow.txt"; \
		sudo pt-query-digest --limit 15 --type slowlog "$$report/mysql.log" > "$$report/pt-query-digest.txt"; \
		printf 'Analysis: %s\n' "$$report"; \
		if [ -n "$(WEBHOOK_URL)" ]; then \
			for name in alp mysqldumpslow pt-query-digest; do \
				curl -fsS -X POST -F "txt=@$$report/$$name.txt" "$(WEBHOOK_URL)" -o /dev/null; \
			done; \
		fi

# DBに接続する
.PHONY: db
db:
	mysql -h "$(MYSQL_HOST)" -P "$(MYSQL_PORT)" -u "$(MYSQL_USER)" -p"$(MYSQL_PASS)" "$(MYSQL_DBNAME)"

# tbls
.PHONY: tbls
tbls:
	tbls doc --force "mysql://$(MYSQL_USER):$(MYSQL_PASS)@$(MYSQL_HOST):$(MYSQL_PORT)/$(MYSQL_DBNAME)"

.PHONY: slow-on
slow-on:
	sudo mysql -e "set global slow_query_log_file = '$(DB_SLOW_LOG)'; set global long_query_time = 0; set global slow_query_log = ON;"

.PHONY: slow-off
slow-off:
	sudo mysql -e "set global slow_query_log = OFF;"

.PHONY: stat
stat:
	@tmux split-window -h -p 50
	@tmux split-window -v -p 50
	@tmux select-pane -t 0
	@tmux split-window -v -p 50
	@tmux send-keys -t 0 "sudo journalctl -u $(SERVICE_NAME) -f" C-m
	@tmux send-keys -t 2 "htop" C-m
	@tmux send-keys -t 3 "dstat" C-m

# 主要コマンドの構成要素 ------------------------

.PHONY: set-nginx-alp-ltsv
set-nginx-alp-ltsv:
	sudo python3 scripts/nginx_ltsv.py --config "$(NGINX_CONFIG)" \
		--access-config "$(NGINX_ACCESS_CONFIG)" --log "$(NGINX_LOG)"
	sudo systemctl reload "$(NGINX_SERVICE)"

.PHONY: install-tools
install-tools:
	sudo apt-get update
	sudo apt-get install -y percona-toolkit dstat git unzip graphviz tree htop tmux python3
	sudo apt-get install -y build-essential curl wget vim
	@work=$$(mktemp -d); trap 'rm -rf -- "$$work"' EXIT; \
		curl -fL --retry 3 "https://github.com/tkuchiki/alp/releases/download/v$(ALP_VERSION)/alp_linux_$(ALP_ARCH).zip" -o "$$work/alp.zip"; \
		unzip -q "$$work/alp.zip" -d "$$work"; \
		sudo install -m 755 "$$work/alp" /usr/local/bin/alp; \
		curl -fL --retry 3 "https://github.com/k1LoW/tbls/releases/download/v$(TBLS_VERSION)/tbls_$(TBLS_VERSION)-1_$(ALP_ARCH).deb" -o "$$work/tbls.deb"; \
		sudo dpkg -i "$$work/tbls.deb"

.PHONY: install-netdata
install-netdata:
	sudo apt-get install -y netdata

.PHONY: git-setup
git-setup:
	git config --local user.name "$(GIT_USER_NAME)"
	git config --local user.email "$(GIT_USER_EMAIL)"

.PHONY: check-server-id
check-server-id:
	@[[ "$(SERVER_ID)" =~ ^[a-zA-Z0-9][a-zA-Z0-9_-]*$$ ]] || { printf 'Set a valid SERVER_ID in %s\n' "$(ENV_FILE)" >&2; exit 1; }
	@printf 'SERVER_ID=%s\n' "$(SERVER_ID)"

.PHONY: set-as-s1 set-as-s2 set-as-s3
set-as-s1 set-as-s2 set-as-s3: init-env
	@sed -i '/^SERVER_ID[[:space:]]*[?+:]*=/d' "$(ENV_FILE)"
	@printf 'SERVER_ID=%s\n' "$(@:set-as-%=%)" >> "$(ENV_FILE)"

.PHONY: get-db-conf
get-db-conf: check-server-id
	mkdir -p "./$(SERVER_ID)/etc/mysql"
	sudo cp -a "$(DB_PATH)/." "./$(SERVER_ID)/etc/mysql/"
	sudo chown -R "$(APP_USER)" "./$(SERVER_ID)/etc/mysql"

.PHONY: get-nginx-conf
get-nginx-conf: check-server-id
	mkdir -p "./$(SERVER_ID)/etc/nginx"
	sudo cp -a "$(NGINX_PATH)/." "./$(SERVER_ID)/etc/nginx/"
	sudo chown -R "$(APP_USER)" "./$(SERVER_ID)/etc/nginx"

.PHONY: get-service-file
get-service-file: check-server-id
	mkdir -p "./$(SERVER_ID)/etc/systemd/system"
	sudo cp "$(SYSTEMD_PATH)/$(SERVICE_NAME)" "./$(SERVER_ID)/etc/systemd/system/$(SERVICE_NAME)"
	sudo chown "$(APP_USER)" "./$(SERVER_ID)/etc/systemd/system/$(SERVICE_NAME)"

.PHONY: get-envsh
get-envsh: check-server-id
	mkdir -p "./$(SERVER_ID)/home/isucon"
	@if [ -f "$(APP_ENV)" ]; then \
		install -m 600 "$(APP_ENV)" "./$(SERVER_ID)/home/isucon/env.sh"; \
	else printf 'No application env file: %s (skipped)\n' "$(APP_ENV)"; fi

.PHONY: deploy-db-conf
deploy-db-conf: check-server-id
	sudo cp -a "./$(SERVER_ID)/etc/mysql/." "$(DB_PATH)/"

.PHONY: deploy-nginx-conf
deploy-nginx-conf: check-server-id
	sudo cp -a "./$(SERVER_ID)/etc/nginx/." "$(NGINX_PATH)/"

.PHONY: deploy-service-file
deploy-service-file: check-server-id
	sudo cp "./$(SERVER_ID)/etc/systemd/system/$(SERVICE_NAME)" "$(SYSTEMD_PATH)/$(SERVICE_NAME)"

.PHONY: deploy-envsh
deploy-envsh: check-server-id
	@if [ -f "./$(SERVER_ID)/home/isucon/env.sh" ]; then \
		install -m 600 "./$(SERVER_ID)/home/isucon/env.sh" "$(APP_ENV)"; \
	else printf 'No application env snapshot (skipped)\n'; fi

.PHONY: build
build:
	cd "$(BUILD_DIR)" && go build -o "$(BIN_NAME)"

.PHONY: restart restart-app
restart:
	sudo systemctl daemon-reload
	sudo systemctl restart "$(DB_SERVICE)"
	sudo systemctl restart "$(NGINX_SERVICE)"
	sudo systemctl restart "$(SERVICE_NAME)"

restart-app:
	sudo systemctl daemon-reload
	sudo systemctl restart "$(SERVICE_NAME)"

.PHONY: mv-logs
mv-logs: check-server-id
	@mkdir -p "$(LOG_DIR)"
	@archive=$$(mktemp -d "$(LOG_DIR)/$$(date -u +%Y%m%dT%H%M%SZ)-XXXXXXXX"); \
		if sudo test -f "$(NGINX_LOG)"; then \
			sudo mv -- "$(NGINX_LOG)" "$$archive/nginx"; \
		fi; \
		sudo touch -- "$(NGINX_LOG)"; \
		sudo systemctl restart "$(NGINX_SERVICE)"; \
		if sudo test -f "$(DB_SLOW_LOG)"; then \
			sudo mv -- "$(DB_SLOW_LOG)" "$$archive/mysql"; \
		fi; \
		sudo touch -- "$(DB_SLOW_LOG)"; \
		sudo chown "$(MYSQL_OS_USER):$(MYSQL_OS_GROUP)" "$(DB_SLOW_LOG)"; \
		sudo chmod 640 "$(DB_SLOW_LOG)"; \
		sudo systemctl restart "$(DB_SERVICE)"; \
		printf 'Saved logs: %s\n' "$$archive"

.PHONY: watch-service-log
watch-service-log:
	sudo journalctl -u "$(SERVICE_NAME)" -n10 -f

.PHONY: netdata-setup
netdata-setup:
	sudo cp -R $(NETDATA_CUSTOM_HTML) $(NETDATA_WEBROOT_PATH)
	sudo systemctl restart netdata
