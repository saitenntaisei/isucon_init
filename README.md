# isucon_init

ISUCON の初期設定・ビルド・計測を `make` で行うためのリポジトリ。
**サーバーごとに `env.sh` を設定したら、以降は基本的に `make` コマンドで進める。**

## SSH agent を使って競技サーバーから GitHub に接続する

管理下の競技サーバーで、手元の SSH agent に登録済みの GitHub 用の鍵を使う場合は、
接続時に `-A` を付ける。`server.example` は対象サーバーに置き換える。

```bash
# 手元で実行し、GitHub 用の鍵が agent にあることを確認する
ssh-add -l
ssh -A isucon@server.example
```

サーバー内の checkout で接続を確認する。

```bash
cd ~/isucon_init
git ls-remote origin HEAD
git fetch origin
```

SSH ログインに使えた鍵が、サーバー内の Git に自動で引き継がれるわけではない。
サーバー側で `Permission denied (publickey)` になる場合は、手元の agent に鍵があることと
接続時の `-A` を確認する。転送した agent を使う接続では、同じ認証で `git push` も行える。

## サーバーごとの設定値を Make に渡す

Ubuntu / Debian 系、Go、MySQL / MariaDB、nginx、systemd を前提とする。
競技用ユーザーで SSH し、Go と大会配布のアプリが配置済みのサーバーで実行する。
この repo の `webapp/` にアプリ本体は含まれない。

## 試合開始時

各サーバーで、以下を上から実行する。GitHub への SSH 接続、Git、Make、sudo が必要。

```bash
git clone git@github.com:saitenntaisei/isucon_init.git
cd isucon_init
make init-env
${EDITOR:-vi} env.sh
make check
make setup
make get-conf
```

既に clone 済みなら、そのディレクトリで `make init-env` から進める。
`make init-env` は [設定例](env.sh.example) をコピーし、既存の `env.sh` は保持する。
初期スコアを記録する場合は、`make setup` より前に大会指定のベンチマーカーを実行する。

`env.sh` では、主に以下を大会環境に合わせる。

| 設定 | 用途 |
| --- | --- |
| `SERVER_ID` | サーバーの識別子。例: `s1` / `s2` / `s3` |
| `APP_USER` | 設定コピーの所有者となる競技用ユーザー |
| `BUILD_DIR` / `BIN_NAME` | Go アプリのディレクトリと出力バイナリ名 |
| `SERVICE_NAME` / `DB_SERVICE` / `NGINX_SERVICE` | systemd のサービス名 |
| `NGINX_CONFIG` / `NGINX_ACCESS_CONFIG` | nginx.conf と、対象の `access_log` が書かれた設定ファイル |
| `NGINX_LOG` / `DB_SLOW_LOG` | 計測するログのパス |
| `MYSQL_*` | DB 接続情報、DB プロセスの OS ユーザー・グループ |
| `WEBHOOK_URL` | 集計結果の送信先。通知しない場合は空欄 |

`env.sh` は Make の代入形式で書く。値を引用符で囲まず、`source` する必要はない。
シェルで export した変数だけでも使える。優先順位は **make の引数 → env.sh → export → 既定値**。
認証情報を含む `env.sh` とサーバー別のコピーは Git 管理対象外。

`make setup` は次の処理を順に行う。

1. 初期設定とアプリを `local/start-<SERVER_ID>-*/original.tar.gz` に保存。
2. alp、tbls、DB 解析ツールなどをインストール。
3. `GIT_USER_NAME` / `GIT_USER_EMAIL` をこの repo の Git 設定に反映。
4. 対象の nginx アクセスログを LTSV に変更し、構文確認後に reload。

nginx の設定処理は繰り返し実行でき、構文確認に失敗した場合は変更前の内容へ戻す。
バックアップには DB のデータは含まれない。`make get-conf` で取得した設定も、秘密情報を除いてからコミットする。

## ビルド・ベンチ・集計

```bash
make bench
# ここで大会指定のベンチマーカーを実行する
make slow-off analyze
```

`make bench` は **ビルド → スロークエリ記録停止 → ログ退避 → 再起動 → 記録開始** の順に処理する。
ベンチマーカーの起動方法は大会ごとに異なるため、そこだけは大会の手順に従う。
サービスを再起動するので、他のベンチを実行中には呼び出さない。

- 退避ログ: `<SERVER_ID>/logs/<UTC日時>-<ランダム文字列>/`
- 生ログと集計結果: `<SERVER_ID>/logs/analysis-<ランダム文字列>/`

過去のログは自動削除しない。`make analyze` は保存先を表示し、`WEBHOOK_URL` が設定済みの場合だけ通知する。
`tool-config/alp/config.yaml` の URL グループは isucondition 向けなので、別の問題では適宜変更する。
最終スコアの計測時は `make slow-off` で全クエリの記録を停止し、同じ条件で比較する。

## よく使うコマンド

| コマンド | 処理 |
| --- | --- |
| `make` | コマンド一覧 |
| `make backup` | 現在の設定とアプリをバックアップ |
| `make build` | アプリのビルドのみ |
| `make restart` | DB・nginx・アプリを再起動 |
| `make get-conf` | 設定をサーバー別ディレクトリへ取得 |
| `make deploy-conf restart` | 保存した設定を配置して再起動 |
| `make alp` / `make slow-query` | 現在のログを個別に集計 |
| `make watch-service-log` | アプリのログを追う |
| `make db` / `make tbls` | DB 接続 / DB ドキュメント生成 |
| `make install-netdata netdata-setup` | 任意の Netdata 導入とダッシュボード配置 |
