# 大きなバイナリだけprepared statementへ分ける

画像などのBLOB書込みがGoのCPUを使う場合、SQL実行時間だけでなく、DBへ送る前の変換を調べる。
`go-sql-driver/mysql` の `interpolateParams` は短いSQLの往復削減に役立つ一方、
大きな `[]byte` をSQL文字列へエスケープする費用が目立つ場合がある。
対象の書込みだけ再利用するprepared statementへ分け、実際の呼出し経路と得点で比較する。

## 1. prepare回数とバイト列変換を分けて観測する

パラメータ付きのSQLを毎回prepare・execute・closeしている場合、短いSQLでも固定費が掛かる。
driverによるパラメータ補間は、この一時的なprepareを避けられる候補になる。
ただし文字列への補間では、バイナリ内の引用符・バックスラッシュなどを表現するための走査やコピーが必要になる。
データ次第で送信サイズも増える。常に一定倍率で膨らむとは扱わない。

| 観測するもの | 切り分ける費用 |
| --- | --- |
| prepare / execute / closeの回数 | 毎回prepareする固定費、接続の再作成 |
| GoのCPU・allocation profile | JSON、base64、hash、driverのエスケープとコピー |
| SQL件数・時間・送信量 | DB内の処理、プロトコル、実際のpayload量 |
| pool待ち・接続数 | SQL外の変換や接続保持との重なり |
| APIの応答時間・成功数・得点 | 局所の削減が全体へ届いたか |

profileでエスケープ処理が重くても、ネットワーク帯域が律速とは限らない。
DBをRAMに置いても、JSON解析、base64復号、hash計算、SQL文字列化は残る。
実行時間とCPU時間の区別は [計測の手順](isucon-measurement-and-concurrency.md) を参照する。

## 2. 一つのSQLだけ再利用する

MySQLのserver-side prepared statementは、値をSQL本文へ補間せずbinary protocolのパラメータとして渡す。
大きなBLOBではこの方式を試し、小さいSQLのdriver設定を同時に変更しない。
対象SQLの内容とトランザクション境界を保ち、最初は転送方法だけを比較する。

GoではDBの所有者が初期化時に `*sql.Stmt` を作り、要求間で再利用する。
以下の `existingSQL` は、すでに使っているパラメータ付きSQLを表す。

```go
// 起動時: 成功したstmtをサービスのフィールドに保持する。
stmt, err := db.PrepareContext(ctx, existingSQL)
if err != nil {
    return err
}

// 要求時: payloadは復号済みの[]byte。SQL文字列に連結しない。
result, err := stmt.ExecContext(requestContext, payload, objectID)
if err != nil {
    return err
}
// resultから必要なIDや更新行数を確認し、既存の応答規約を保つ。
// 受付停止後、所有者の終了処理でstmt.Close()する。
```

`DB.PrepareContext` で作ったStmtは複数goroutineから利用できる。
ただしDB pool全体でサーバー側のprepareが1回だけになる保証はない。
物理接続ごとにprepareされ、接続の作り直しでも再prepareが起きるため、prepare数と接続寿命を測る。
`Conn` や `Tx` から作ったStmtはその接続・トランザクションへ束縛される。
既存のTx内で実行するなら `tx.StmtContext` などで結び、誤ってDB直結のautocommitへ出さない。
Stmtを要求ごとに作って閉じると、減らしたかったprepareの固定費が戻る。

prepare失敗時は起動を失敗させるか、元のパラメータ付き実行へ戻すかを明示する。
fallbackが続くなら観測できるようにし、一時的な初回失敗で永久に固定されない設計を選ぶ。
実行エラーの後に無条件で別方式を再実行しない。commit結果不明なら二重書込みになり得る。
driverの版、SQL mode、payloadサイズで経路が変わるため、カウンタとprofileで確認する。

## 3. バイト列と更新の意味を変えない

送る値は元画像の `[]byte` のままにする。base64文字列や文字コード変換した文字列で代用しない。
NUL、引用符、バックスラッシュ、非UTF-8のバイトを含むpayloadで保存・読出しが完全一致するか確かめる。
空データとNULL、上限サイズ、DBのpacket制限、取消時のエラーも従来とそろえる。
再利用するbufferは、実行が完了するまで書き換えない。

SQLの変更は別候補にする。例えばREPLACEには削除と挿入、一意制約、採番、トリガーの意味がある。
prepared statementを使うためにUPDATEをREPLACEへ変える必要はない。
SQL injection対策はdriverのパラメータ処理へ任せ、独自エスケープや文字列連結に置き換えない。
認証、権限、パスワードのhash方式やcostは、この転送最適化の対象に含めない。

## 4. JSON・base64・hashは別候補として扱う

JSON内のbase64が大きい場合も、まず標準decoderを保ったままDB転送の効果を測る。
JSONの文字列を単純に検索・切り出す方式は、エスケープ、重複キー、不正な構文で意味が変わり得る。
通常形だけを速く処理するなら、その入力が完全に妥当なJSONであることを確認できる必要がある。
疑わしい形は既存decoderへ戻し、速い経路が不正入力を受理しないことを差分検証する。
キー順序、空白、エスケープ、未知フィールド、重複キー、欠落、null、末尾データ、壊れたbase64を含める。
返す値だけでなく、受理・拒否とエラー応答もそろえる。ベンチで観測した形だけに仕様を狭めない。
本文全体を読む場合は従来のサイズ制限を維持し、allocationとピークメモリも測る。

画像のhashを生成列へ移せばGoのCPUが減ることはあるが、DB側の計算と書込みは増える。
保存する元バイト列、hash方式、hexの大小文字、更新反映期限を維持する。
画像とhashを別の時点から読んで混在させない。CPUを移した先も同じ負荷区間で測る。
許されていないhash方式やcostの変更で、計算そのものを省略しない。

## 5. CPU減少と増点を別々に報告する

過去の実験では、base64の直接復号とBLOB書込みのprepared化をまとめた候補でGoのCPUが減った。
ただし得点は変更前に観測された範囲内にあり、個別施策の寄与や増点効果は確定していない。
この観測はプロトコル費用を調べる手掛かりであり、独自JSON parserを一般化する根拠ではない。

次の比較では、prepare再利用、JSON処理、hashの配置を独立した候補にする。
同じpayload分布・成功数・負荷区間でCPU、allocation、送信量、API時間と得点を保存する。
削減したCPUが別の律速へ移る場合もあるため、全ホストの変化を確認する。
採用基準は [改善ループ](isucon-playbook.md#3-改善ループ) と
[得点を決める待ち時間とCPUの区別](isucon-measurement-and-concurrency.md#8-得点が往復時間で決まるかcpuで決まるかを分ける) に合わせる。
