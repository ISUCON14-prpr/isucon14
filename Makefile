

SERVICE_NAME := isuride
DEFAULT_LANGUAGE := go
LANGUAGE := rust

# ------------------------------------------------------------
# 最初のセットアップ　　DEFAULT_LANGUAGからLANGUAGEに
.PHONY: setup
setup: install_alp install_pt_query_digest mysql-setting-cp-to-webapp nginx-setting-cp-to-webapp make-log-dir
# ------------------------------------------------------------
# ------------------------------------------------------------
# 言語を変更する
.PHONY: change-language
change-language: stop-$(DEFAULT_LANGUAGE) start-$(LANGUAGE)
# ------------------------------------------------------------
# デプロイ
.PHONY: deploy
deploy: git-pull build mysql-setting-cp-from-webapp nginx-setting-cp-from-webapp  log-permit del-log-file restart-service restart-nginx restart-mysql 
# ------------------------------------------------------------
# ------------------------------------------------------------
# ベンチを叩く＆ログを取得するls
.PHONY: analyze
# bench: del-log-file mysql-setting-cp-from-webapp nginx-setting-cp-from-webapp exec-bench log-permit exec-query-digest exec-alp
# 本番はこっち
bench:  log-permit exec-query-digest exec-alp
# ------------------------------------------------------------

.PHONY: install_alp
install_alp:
	@echo "Installing alp..."
	cd ~ && \
	wget https://github.com/tkuchiki/alp/releases/download/v1.0.12/alp_linux_amd64.tar.gz && \
	tar xzf alp_linux_amd64.tar.gz && \
	sudo install alp /usr/local/bin/alp && \
	rm alp_linux_amd64.tar.gz

# library2のインストール
.PHONY: install_pt_query_digest
install_pt_query_digest:
	@echo "Installing pt_query_digest..."
	sudo apt install percona-toolkit

# コピー先: /home/isucon/webapp/etc/mysql
.PHONY: mysql-setting-cp-to-webapp
mysql-setting-cp-to-webapp:
	@echo "Copying MySQL all config files to /home/isucon/webapp/etc/mysql..."
	sudo mkdir -p /home/isucon/webapp/etc/mysql
	sudo cp -r /etc/mysql/* /home/isucon/webapp/etc/mysql/
	sudo chown -R isucon:isucon /home/isucon/webapp/etc/mysql
	sudo chmod -R u+rwX,g+rwX,o+rX /home/isucon/webapp/etc/mysql
	@echo "Copy completed."

# コピー先: /home/isucon/webapp/etc/nginx
.PHONY: nginx-setting-cp-to-webapp
nginx-setting-cp-to-webapp:
	@echo "Copying nginx all config files to /home/isucon/webapp/etc/nginx..."
	sudo mkdir -p /home/isucon/webapp/etc/nginx
	sudo mkdir -p /home/isucon/webapp/etc/nginx/sites-available
	sudo cp -r /etc/nginx/nginx.conf /home/isucon/webapp/etc/nginx/nginx.conf
	sudo cp -r /etc/nginx/sites-available/isuride.conf /home/isucon/webapp/etc/nginx/sites-available/isuride.conf
	sudo chown -R isucon:isucon /home/isucon/webapp/etc/nginx
	sudo chmod -R u+rwX,g+rwX,o+rX /home/isucon/webapp/etc/nginx
	@echo "Copy completed."



.PHONY: make-log-dir
make-log-dir:
	mkdir -p /home/isucon/webapp/logs/
	mkdir -p /home/isucon/webapp/logs/access_logs
	mkdir -p /home/isucon/webapp/logs/slow_query_logs;
	@echo "これが終わったら、nginx.confでaccesslogのformatをかく。mysqld.confでslowlogの設定をする。"



.PHONY: del-log-file
del-log-file:
	rm -f /var/log/mysql/mysql-slow.log
	rm -f /var/log/nginx/access.log

# コピー元: /home/isucon/webapp/etc/mysql
.PHONY: mysql-setting-cp-from-webapp
mysql-setting-cp-from-webapp:
	@echo "Restoring MySQL all config files from /home/isucon/webapp/etc/mysql..."
	sudo cp -r /home/isucon/webapp/etc/mysql/* /etc/mysql/
	sudo systemctl restart mysql.service
	@echo "Restore completed."

# コピー元: /home/isucon/webapp/etc/nginx
.PHONY: nginx-setting-cp-from-webapp
nginx-setting-cp-from-webapp:
	@echo "Copying nginx all config files from /home/isucon/webapp/etc/nginx to /etc/nginx..."
	sudo cp /home/isucon/webapp/etc/nginx/nginx.conf /etc/nginx/nginx.conf
	sudo cp /home/isucon/webapp/etc/nginx/sites-available/isuride.conf /etc/nginx/sites-available/isuride.conf
	sudo systemctl reload nginx
	@echo "Copy and reload completed."

.PHONY: exec-bench
exec-bench:
	../bench run --enable-ssl

.PHONY: log-permit
log-permit:
	sudo chmod 777 /var/log/nginx /var/log/nginx/*
	sudo chmod 777 /var/log/mysql /var/log/mysql/*

.PHONY: exec-alp
exec-alp:
	current_date=$$(date +"%Y%m%d-%H%M%S") && \
	cat /var/log/nginx/access.log | alp ltsv --sort sum --reverse > "/home/isucon/webapp/logs/access_logs/result-$$current_date.txt"

.PHONY: exec-query-digest
exec-query-digest:
	current_date=$$(date +"%Y%m%d-%H%M%S") && \
	pt-query-digest /var/log/mysql/mysql-slow.log > "/home/isucon/webapp/logs/slow_query_logs/result-$$current_date.txt"


.PHONY: stop-$(DEFAULT_LANGUAGE)
stop-$(DEFAULT_LANGUAGE):
	sudo systemctl disable --now $(SERVICE_NAME)-$(DEFAULT_LANGUAGE).service

.PHONY: start-$(LANGUAGE)
start-$(LANGUAGE):
	sudo systemctl enable --now $(SERVICE_NAME)-$(LANGUAGE).service

.PHONY: status
status:
	sudo systemctl status $(SERVICE_NAME)-$(LANGUAGE).service

.PHONY: git-pull
git-pull:
	@current_branch=$$(git rev-parse --abbrev-ref HEAD) && \
	echo "今は$$current_branchブランチです"

	@current_branch=$$(git rev-parse --abbrev-ref HEAD); \
	echo "今は$$current_branchブランチです。このブランチで作業を続けますか? [y/N]:"; \
	read ans; \
	case "$$ans" in \
		[yY]|[yY][eE][sS]) \
			echo "作業を続けます。"; \
			;; \
		*) \
			echo "作業を中断します。"; \
			exit 1; \
			;; \
	esac
	@echo "git pull"

	git pull origin $$current_branch

.PHONY: build-and-restart
restart-nginx:
	sudo systemctl restart nginx

.PHONY: restart-mysql
restart-mysql:
	sudo systemctl restart mysql

.PHONY: build
build:
ifeq ($(LANGUAGE),rust)
	cd $(LANGUAGE) && cargo build --release
else ifeq ($(LANGUAGE),go)
	cd $(LANGUAGE) && go build -o $(SERVICE_NAME)
else
	@echo "Unsupported language specified or LANGUAGE variable is not set"
endif

.PHONY: restart-service
restart-service:
	sudo systemctl restart $(SERVICE_NAME)-$(LANGUAGE).service

# alpのformat
# log_format ltsv "time:$time_local"
#         "\thost:$remote_addr"
#         "\tforwardedfor:$http_x_forwarded_for"
#         "\treq:$request"
#         "\tstatus:$status"
#         "\tmethod:$request_method"
#         "\turi:$request_uri"
#         "\tsize:$body_bytes_sent"
#         "\treferer:$http_referer"
#         "\tua:$http_user_agent"
#         "\treqtime:$request_time"
#         "\tcache:$upstream_http_x_cache"
#         "\truntime:$upstream_http_x_runtime"
#         "\tapptime:$upstream_response_time"
#         "\tvhost:$host";

# adsfsdaf