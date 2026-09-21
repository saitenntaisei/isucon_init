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

## transaction 内のファイル生成を短くする

DB transaction 内で外部コマンドによるファイルコピーや archive 生成を行うと、その間も
接続や lock を保持する。transaction の SQL 間隔を handler と照合し、ファイル処理が保持時間の
候補だと確認できた場合は、形式と命名規則を維持できる範囲で、元ファイルから archive writer へ
直接 stream する実装を比較する。最初の比較では transaction 境界を変えず、外部 process と
中間コピーの除去だけを一つの変更として測る。transaction の外へ移す判断は、読み取り中の更新、
snapshot、失敗時の再実行を含む整合性の検討として分ける。

生成途中のファイルを利用者に見せないため、出力先と同じ filesystem の一意な一時ファイルへ
書き込む。archive writer とファイルの `Close` エラーを確認し、両方が成功した後に同一 filesystem
内の rename で atomic に置き換える。失敗時は一時ファイルだけを削除し、既存の成果物を残す。
空の archive、entry の名前・件数・内容、同名ファイル、並行実行、途中失敗後の cleanup も確認する。

Store と Deflate は形式上どちらも利用できても、性能特性は異なる。Store は圧縮 CPU を使わない
代わりに出力が大きくなる場合があり、Deflate はその逆になり得る。実際の入力で出力 byte 数と
処理時間を測り、HTTP の遅延・成功失敗、スコア、transaction 保持時間や pool 待ち、process または
system 全体の CPU と合わせて採否を決める。子 process の処理を Go 内へ移すと Go pprof に見える
CPU が増える場合があるため、それだけを CPU 総量の増加とは判断しない。
