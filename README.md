# traP-isucon-newbie-handson2022

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

Makefile は repo 直下の `env.sh` を読み込む。大会配布の `~/env.sh` とは別のファイルとして用意する。
既存ファイルがある場合は内容を確認し、上書きしない。

```bash
if [ ! -e env.sh ] && [ ! -L env.sh ]; then
  (umask 077; printf 'SERVER_ID=s1\n' > env.sh)
fi
```

通常の Makefile 内の代入は、シェルで export した環境変数より優先される。
ビルド先やサービス名をサーバーに合わせる場合は、Make のコマンドライン引数で渡す。
以下は Bash で実行し、先頭の値を対象サーバーに合わせる。

```bash
SERVER_ID=s1
APP_DIR=/path/to/webapp/go
APP_BINARY=app
APP_SERVICE=app.service

server_make() {
  make -j1 "SERVER_ID=$SERVER_ID" "BUILD_DIR=$APP_DIR" \
    "BIN_NAME=$APP_BINARY" "SERVICE_NAME=$APP_SERVICE" "$@"
}

# パス・サービス名を確認する。ビルドや再起動は実行しない。
server_make -n build restart
```

`make bench` はログの退避・ビルド・サービス再起動・スロークエリ記録の開始を行う。
ベンチマーカー自体は起動しない。競技用サーバーで操作内容を確認し、大会指定の手順で実行する。

## ベンチマークのログを保存する

`server_make mv-logs` と `server_make bench` は、既存の nginx / MySQL ログを
`<SERVER_ID>/logs/<UTC日時>-<ランダム文字列>/` に退避する。
同じ秒に実行しても保存先は別になり、以前の計測結果も残る。
直接 `mv-logs` を呼ぶ場合も `SERVER_ID` の設定が必要。

退避ログは `nginx` と `mysql` の名前で保存される。元のログが存在しない場合はその分の
退避ファイルは作らない。移動に失敗した場合はエラーで停止し、その後の操作に進まない。
この処理は nginx / MySQL を再起動するため、ベンチ実行中には呼び出さない。

退避後のログを比較し、必要な生ログと集計結果を保存してから、不要な過去の保存先だけを
明示的に削除する。ログ削除をベンチ前処理に組み込まない。`logs/` は Git 管理対象外で、
アクセスログなどに含まれる認証情報や個人情報を PR に載せない。
