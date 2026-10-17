# 各回から引ける汎用パターンと出典

調査日: 2026-10-17。[共通手順書へ戻る](isucon-playbook.md)。
ISUCON1〜14の公開公式資料を横断した索引。予選と本選の区別は各リンクに従う。
各行はその回から取り出せる事例であり、当日のすべての課題や最適解を網羅するものではない。
右列の判断は、公式資料に記された事例から本書で一般化した提案である。

| 回・資料 | 資料中の事例 | 共通フローでの使い方 |
| --- | --- | --- |
| [1: 公式再現手順](https://isucon.net/archives/30155170.html) | 初期データや負荷設定で測定結果が変わる | データ量・ベンチ配置・負荷条件をそろえて基準値を取る |
| [2: 公式再現手順](https://isucon.net/archives/30154200.html) | チケットの販売数と完売時間を評価 | HTTP件数から加点される完了処理へ視点を移す |
| [3予選: 講評](https://isucon.net/archives/32951806.html) | ログイン・非公開投稿、複数のキャッシュ戦略 | 利用者・権限で応答が違う単位を識別し、正しいキーと更新契約を設計 |
| [4予選: 解説](https://isucon.net/archives/40724693.html) | ログイン履歴の繰返し集計と再起動後のreport | カウンタ等の派生状態と永続データを両立させる |
| [5予選: 解説](https://isucon.net/archives/45627361.html) | 一覧を作る際のN+1と不要な本文取得 | 問い合わせ回数と転送量を減らし、権限条件を維持 |
| [6予選: 解説](https://isucon.net/archives/48697611.html) | サービス間の往復とキーワードリンク生成 | DB以外の通信・正規表現・重複計算もprofileで確認 |
| [7予選: 解説](https://isucon.net/archives/50961706.html) | 画像配信、複数台、通知のbatch化 | 配信とイベント処理を、許容遅延・帯域・共有状態から設計 |
| [8本選: 解説](https://isucon.net/archives/52598691.html) | 外部APIの遅延、一括送信、流入増加 | 外部呼出しの固定費と得点につながる負荷制御を調べる |
| [9予選: 解説](https://isucon.net/archives/53789931.html) | 売上、同時購入、外部サービス、二重決済 | 加点経路を追い、競合と外部副作用を一度だけ成立させる |
| [10本選: 解説](https://isucon.net/archives/55140539.html) | 大きな集計SQLと実際の律速の違い | 見た目で修正順を決めず、現在の負荷を計測 |
| [11予選: 解説](https://isucon.net/archives/56044867.html) | 大量の状態書込みと読取り、典型的な課題 | 頻出の定石でも得点経路の律速へ当てて検証 |
| [12予選: 解説](https://isucon.net/archives/56850281.html) | tenant別SQLite、MySQL移行、複数の解法 | DB移行や複数台化を必須にせず、現在の制約と費用で選択 |
| [13: 解説](https://isucon.net/archives/58001272.html) | Tipsを評価、N+1、画像hash、DNS負荷 | 加点へ至る行動と、アプリ外の依存サービスも含めて計測 |
| [14: 解説](https://isucon.net/archives/58869617.html) | 配車・通知・座標更新が連動し、SSEは必須ではない | 個別APIの時間に加え、待機・割当・利用者の循環を調べる |

## 一般化の境界

1. **固定数値をコピーしない。** TTL、許容遅延、batchサイズ、台数、接続数、追試基準は当該回の仕様と実測から決める。
2. **過去の実装をそのまま移植しない。** データ構造、DB・言語・ミドルウェアの版、初期化方法、更新経路を照合する。
3. **ベンチの成功だけで仕様適合を保証しない。** 権限、表示、永続化など、当該回で要求される契約を確認する。
4. **採用理由を記録する。** 局所指標の改善と全体スコアの改善を区別し、試行の揺らぎを残す。

特に3予選の講評には当時のチェックの特性を利用した戦略、7予選の解説にはキャッシュ挙動の調整経緯が記されている。
ここから別の回に持ち込むのは「当該回の仕様と測定条件を確認する」という判断である。
[3予選公式講評](https://isucon.net/archives/32951806.html)、
[7予選公式解説](https://isucon.net/archives/50961706.html)。

## ツールの一次資料

| 資料 | 本書で確認に使った内容 |
| --- | --- |
| [alp](https://github.com/tkuchiki/alp) | URLの集約、件数・時間・分位値・HTTPステータスの比較 |
| [pt-query-digest](https://docs.percona.com/percona-toolkit/pt-query-digest) | 同形SQLの件数、総時間、平均、分位値 |
| [Go Diagnostics](https://go.dev/doc/diagnostics) | CPU・heap・goroutine・block・mutex・traceの用途と計測の影響 |
| [MySQL Multiple-Column Indexes](https://dev.mysql.com/doc/refman/8.0/en/multiple-column-indexes.html) | 複合索引と左端の列の組合せ |
| [nginx proxy_buffering](https://nginx.org/en/docs/http/ngx_http_proxy_module.html#proxy_buffering) | proxyのbufferingと`X-Accel-Buffering` |

コマンドや設定の細部は実際に使うバージョンの資料で再確認する。
