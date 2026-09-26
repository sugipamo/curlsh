# curlsh

Debian 12/13のVM、Proxmox LXC、物理機へ、選んだ開発用ツールをAnsibleでセットアップします。
OSはDebianの公式イメージを使い、このリポジトリが追加ソフトウェアを管理します。

## 使い方

リポジトリを取得した後、対象マシン上でrootとして実行します。

```bash
git clone https://github.com/sugipamo/curlsh.git
cd curlsh
sudo ./bootstrap.sh
```

対話モードでは`gum`のチェックリストから部品を選びます。`gum`がない場合は先に
署名付きCharm APTリポジトリからインストールします。選択後に内容を表示し、確認してから
Ansibleを実行します。

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

`v0.1.0`タグの1ファイルだけを取得しても、同じタグの
リポジトリ全体を取得します。`main`を直接実行する例は掲載しません。
対話モードを使う場合は、先にrootシェルへ入ります（標準入力とTTYが必要です）。

```bash
sudo -i
bootstrap_script=$(mktemp)
curl -fsSL https://raw.githubusercontent.com/sugipamo/curlsh/v0.1.0/bootstrap.sh \
  -o "$bootstrap_script" &&
  bash "$bootstrap_script" --platform vm
rm -- "$bootstrap_script"
```

非対話モードでは標準入力からも実行できます。

```bash
set -o pipefail
curl -fsSL https://raw.githubusercontent.com/sugipamo/curlsh/v0.1.0/bootstrap.sh |
  sudo bash -s -- --ref v0.1.0 --non-interactive --platform vm \
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
ansible-playbook -i localhost, -c local playbook.yml \
  -e bootstrap_platform=vm --syntax-check
```

Ansible roleは繰り返し実行できます。`--components`で指定したroleだけが動きます。
パッケージの更新はAPTの現在の候補版に従うため、実行時期によって結果が変わります。
