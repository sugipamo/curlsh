# 変更仕様 / Change specifications

各部品と実行基盤が変更する範囲を記載します。この文書群はGitHubで読めるだけでなく、
`bootstrap.sh --dry-run`と導入直前の説明でも同じファイルを表示します。
実装が最終的な根拠です。各仕様のImplementationリンクから確認してください。

- [実行基盤・共通の制約](runtime.md)
- [共通の配布元準備](repository_prerequisites.md)
- [基本ツール](base.md)
- [GitHub CLI](github_cli.md)
- [Tailscale](tailscale.md)
- [Codex CLI](codex.md)
- [Docker](docker.md)
- [Node.js / npm](nodejs.md)
- [開発ツール](devtools.md)
- [QEMU guest agent](qemu_guest_agent.md)

## 読み方

`Packages`は明示的に指定するパッケージであり、APTが追加する依存・推奨パッケージの
完全な一覧ではありません。`Writes`はレシピが直接管理する主なファイルです。
パッケージの展開先、maintainer script、サービスのデータ・ログ、外部インストーラーの
全書き込み先まで網羅するものではありません。

`Uncertain`には、実行時の配布元や既存環境次第で変わる部分を明示しています。
`Does not run`はcurlshが自動実行しない操作です。パッケージ自体の副作用がないことや、
他の管理ツールが同じ操作をしないことまで保証するものではありません。

`--dry-run`は仕様とローカルのパッケージ情報を読む説明モードです。Ansibleのcheck modeや
APTのトランザクション・シミュレーションではありません。表示を保存・適用する機構はなく、
計画の承認から導入までの間に配布元やホストの状態が変わることもあります。
同じタグを読む・実行することでレシピは揃いますが、APTの内容や外部スクリプトは固定されません。
表示は選択順に整理した説明で、実行トレースではありません。roleの実行順は
[playbook.yml](../../playbook.yml)と各roleの依存関係に従います。

## 変更時のルール

role・実行基盤を変更するときは、同じPRで対応する仕様も更新します。
CIでは全部品の仕様・実装リンク・パッケージ一覧・サービス一覧の対応、および
dry-run / キャンセル時に導入処理を呼ばないことを検証します。
この検証は説明の完全性を数学的に保証するものではなく、レビューを補助するものです。
