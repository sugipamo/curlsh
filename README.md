# curlsh

Debian 12/13のVM、Proxmox LXC、物理機へ、選んだ開発用ツールをAnsibleでセットアップします。
OSはDebianの公式イメージを使い、このリポジトリが追加ソフトウェアを管理します。

このブランチは次期v0.2.0の開発版です。新機能はチェックアウトから実行してください。
下記のv0.2.0のダウンロード例は、同名タグの公開後に利用できます。

## 使い方

リポジトリを取得した後、対象マシン上でrootとして実行します。

```bash
git clone https://github.com/sugipamo/curlsh.git
cd curlsh
sudo ./bootstrap.sh
```

対話モードでは、既に`gum`があればチェックリスト、なければBashのテキスト入力で部品を
選びます。どちらも導入状態とバージョンを表示します。メニューのためにパッケージや
Charm APT配布元を追加することはありません。以前追加されたものを自動削除もしません。

選択後、実行基盤を含む変更仕様を表示し、事前チェックを行います。最後に`yes`と入力して
承認するまでAPT・Ansibleによる導入は始まりません。空入力・EOF・Ctrl-Cでのキャンセルも
導入処理に進みません。事前チェックではHTTPS疎通確認、メニューではバージョン照会を行います。

Cloud-Initや自動化では、部品とplatformを明示します。`--non-interactive`と`--components`の
組み合わせを導入の承認として扱い、同じ変更仕様を表示・事前チェック後、確認入力なしで実行します。

```bash
sudo ./bootstrap.sh \
  --non-interactive \
  --platform vm \
  --components base,github_cli,tailscale,codex,qemu_guest_agent
```

変更仕様と現在のパッケージ情報は、root権限なしで確認できます。

```bash
./bootstrap.sh --dry-run --platform lxc \
  --components base,github_cli,tailscale,codex
```

`--dry-run`は、追加する配布元、主な変更ファイル、サービス、競合時・再実行時の挙動、
未確定事項、自動実行しない操作を表示します。GitHub上の[変更仕様](docs/changes/README.md)と
同じ文書を使います。Ansible導入・実行、APT索引更新、配布元への疎通確認、導入済みツールの
バージョンコマンドは実行しません。完全な変更差分やAPT依存解決結果を予測するものではなく、
実行可能かの確認は別途`--check`で行います。どちらも計画・構成情報は保存しません。

単体スクリプトや標準入力からの実行では、`--dry-run`でも同じタグのソースを一時ディレクトリへ
取得し、終了時に削除します。ローカルチェックアウトならこの取得はありません。
ローカル実行は未コミット変更を含む手元のコードを使い、`--ref`では差し替わりません。

`v0.2.0`タグの1ファイルだけを取得しても、同じタグの
リポジトリ全体を取得します。`main`を直接実行する例は掲載しません。
対話モードを使う場合は、先にrootシェルへ入ります（標準入力とTTYが必要です）。

```bash
sudo -i
(
  bootstrap_script=$(mktemp)
  trap 'rm -- "$bootstrap_script"' EXIT
  curl -fsSL https://raw.githubusercontent.com/sugipamo/curlsh/v0.2.0/bootstrap.sh \
    -o "$bootstrap_script" &&
    bash "$bootstrap_script" --platform vm
)
```

非対話モードでは標準入力からも実行できます。

```bash
set -o pipefail
curl -fsSL https://raw.githubusercontent.com/sugipamo/curlsh/v0.2.0/bootstrap.sh |
  sudo bash -s -- --ref v0.2.0 --non-interactive --platform vm \
  --components base,github_cli,tailscale,codex,qemu_guest_agent
```

forkしたリポジトリを使う場合は`--repo OWNER/REPOSITORY`を指定してください。

## 選択できる部品

| 名前 | 内容 | 対象 |
|---|---|---|
| `base` | 証明書、curl、git、jq、SSH client | すべて |
| `github_cli` | 公式APTリポジトリの`gh` | すべて |
| `tailscale` | 公式stable版と`tailscaled`有効化 | すべて |
| `codex` | 固定版Codex CLIと最小PATH向け`/usr/bin/codex` | すべて |
| `docker` | 公式Docker EngineとCompose | VM・物理機 |
| `nodejs` | Debian版Node.jsとnpm | すべて |
| `devtools` | compiler、make、ripgrepなど | すべて |
| `qemu_guest_agent` | QEMU guest agent | VMのみ |

Dockerは初版ではLXC対象外です。`--platform auto`は仮想化環境を推定しますが、
判定が違う場合は`--platform`で指定できます。

各部品の変更範囲・外部依存・再実行時の挙動は[変更仕様一覧](docs/changes/README.md)を
参照してください。固定タグはレシピを揃えるためのもので、APT候補や外部インストーラーまで
固定するものではありません。途中で失敗した場合、それまでの変更を自動で戻す機構はありません。

## 状態確認・事前チェック・更新確認

以下のコマンドはインストールも認証操作も行わず、root権限は不要です。
`--components`を省略すると、指定platformで利用可能な全コンポーネントが対象です。
curlshは選択履歴や構成データを保存せず、毎回OSと実行ファイルを調べます。

```bash
./bootstrap.sh --status --platform lxc
./bootstrap.sh --check --platform lxc --components base,tailscale,codex
./bootstrap.sh --check-updates --platform lxc --components base,tailscale,codex
```

- `--status`: `installed`（パッケージと主要コマンドを検出）、
  `partial`（パッケージ不足・実行失敗・PATH不足）、`missing`を表示します。
  systemdが動いていればサービス状態も表示します。
- `--check`: 対応OS、必要コマンド、空き容量、選択したサービスのsystemd、
  LXCのTUN、VMのQEMU agentチャネル、Dockerの競合パッケージ、
  選択した配布元へのHTTPS接続を確認します。同じチェックを導入前にも実行します。
  curlがない環境ではHTTPS検査をスキップしたことを明示します。
- `--check-updates`: APTのローカル索引の候補版と導入済み版を比較します。
  Codexは導入済み版・curlsh固定版・オンラインの上流安定版を分けて表示します。
  更新は適用しません。取得失敗は`UNKNOWN`として終了コード1で報告します。

APTの更新情報を取得し直す場合は、rootで`apt-get update`を実行してから
`--check-updates`を再実行してください。更新候補がある場合は
`apt-get install --only-upgrade ...`などの次の操作を表示します。
Codexの上流版が新しくても、このリポジトリの固定版は自動変更しません。
導入済みCodexが固定版より新しい場合は、再導入がダウングレードになることを表示します。

空き容量は正確なダウンロード量ではなく、導入作業用の余裕として
256 MiBにCodex/Docker各1 GiB、Node.js/devtools各512 MiBを加えた値で確認します。

導入後は、選択したコマンドの実行・Codexの最小PATH・サービス起動を検証し、
認証確認、ログイン、サービス調査、更新確認のコマンドを表示します。
認証状態は実行ユーザーごとに異なるため、rootの認証情報を読んで判定しません。
表示された認証コマンドは、そのツールを使うユーザーで実行してください。
Ansibleが途中で失敗した場合は、確認結果を表示しても成功扱いにせず、元の終了コードを返します。

## 依存関係

| 対象 | 自動導入する共通前提 |
|---|---|
| 全インストール | ansible-core（未導入時）、python3-apt |
| 対話メニュー | Bash。既にgumがあれば利用するが自動導入はしない |
| github_cli / tailscale / codex / docker | repository_prerequisites roleによるca-certificates、curl、APT keyringディレクトリ |

共通前提はAnsibleのrole依存として定義しているため、Codexだけを選んでも必要な
ダウンロードツールが導入されます。CodexのためにNode.jsやnpmを選ぶ必要はありません。
systemdやProxmoxのデバイス設定は事前条件として検査し、自動変更しません。

## Proxmoxでの流れ

VMはDebian cloud imageからCloneし、Cloud-Initでユーザー、SSH公開鍵、hostname、
DHCPを設定した後にbootstrapを実行します。LXCはProxmox標準のDebianテンプレートで
作成後に実行します。Cloud-Initの例は
[examples/cloud-init-user-data.yml](examples/cloud-init-user-data.yml)、手順は
[docs/proxmox.md](docs/proxmox.md)を参照してください。

Tailscaleへの参加、`tag:agent`、Codexログイン、GitHubログインは各マシンで行います。
認証キー、APIキー、`~/.codex/auth.json`はこのリポジトリに保存しません。

Codexは[OpenAI公式のLinux用スタンドアロンインストーラー](https://learn.chatgpt.com/docs/codex/cli)
を公式URLから取得し、`vars/versions.yml`の固定バージョンを指定して実行します。
インストーラーは固定しないため、初回導入時にはOpenAIの配布元を信頼する設計です。

## 開発・検証

```bash
./tests/test-bootstrap.sh
./tests/test-diagnostics.sh
./tests/test-fetch.sh
./tests/test-boundaries.sh
# PyYAMLが入った開発用Python環境で実行
python3 ./tests/test-specs.py
ansible-playbook -i localhost, -c local playbook.yml \
  -e bootstrap_platform=vm --syntax-check
```

Ansible roleは繰り返し実行できます。`--components`で指定したroleだけが動きます。
パッケージの更新はAPTの現在の候補版に従うため、実行時期によって結果が変わります。

CIはDebian 12/13でCodex単独導入、base追加、再実行、Ansible失敗時の終了コードを検証します。
変更仕様とroleのパッケージ・サービスの対応も確認します。`test-boundaries.sh`は隔離したPATHの
偽コマンドを使ってdry-runを検証し、root実行時にはPTYでキャンセル・EOF・Ctrl-C・承認の境界も
検証します（APTなどの実コマンドは実行しません）。CIでは一般ユーザー・rootの両方で実行します。
Tailscale/Docker/QEMU agentの実サービス起動は、対象のLXC/VMで確認してください。
