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

対話モードでは`gum`のチェックリストから部品を選びます。`gum`がない場合は先に
署名付きCharm APTリポジトリからインストールします。選択後に内容を表示し、確認してから
Ansibleを実行します。各選択肢には、その場で検出した導入状態とバージョンを表示します。

Cloud-Initや自動化では、部品とplatformを明示します。

```bash
sudo ./bootstrap.sh \
  --non-interactive \
  --platform vm \
  --components base,github_cli,tailscale,codex,qemu_guest_agent
```

変更前に引数だけ確認できます。

```bash
./bootstrap.sh --dry-run --non-interactive --platform lxc \
  --components base,github_cli,tailscale,codex
```

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
| 対話メニュー | gum、ca-certificates、curl、gnupg（gum未導入時） |
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
ansible-playbook -i localhost, -c local playbook.yml \
  -e bootstrap_platform=vm --syntax-check
```

Ansible roleは繰り返し実行できます。`--components`で指定したroleだけが動きます。
パッケージの更新はAPTの現在の候補版に従うため、実行時期によって結果が変わります。

CIはDebian 12/13でCodex単独導入、base追加、再実行、Ansible失敗時の終了コードを検証します。
Tailscale/Docker/QEMU agentの実サービス起動は、対象のLXC/VMで確認してください。
