# traP-isucon-newbie-handson2022

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

## MySQL のパラメーター準備コストを調べる

Go の `database/sql` / `sqlx` と `go-sql-driver/mysql` を使うアプリでは、
引数付き SQL のたびにサーバー側の準備処理が発生する場合がある。
スロークエリ集計の `ADMIN PREPARE` が多いときは、索引に加えて接続設定も比較対象にする。

既存の `mysql.Config` で通常リクエスト用の接続に次を指定すると、driver が引数を
エスケープして SQL に補間する。SQL を手作業の文字列連結に書き換える必要はない。

```go
mysqlConfig.InterpolateParams = true
```

初期化用の複文接続など、用途が異なる接続は既存の設定を維持して分けて検証する。
採用している driver のバージョン・文字セット・明示的な prepared statement の使用箇所を確認し、
すべての SQL に同じ効果があるとは想定しない。

変更は一つずつ比較する。`server_make bench`、大会指定のベンチマーカー、
`server_make slow-off` の順に実行し、初期化・負荷試験・最終整合性検証まで完了させる。
同じサーバーとログ条件で、スコア・タイムアウト・SQL 件数・準備処理の累積時間を記録する。
クエリ単体の短縮だけで採用せず、全体の結果が改善した変更を残す。
