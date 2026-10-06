# curlsh

Debian 12/13のVM、Proxmox LXC、物理機へ、選んだ開発用ツールをAnsibleでセットアップします。
OSはDebianの公式イメージを使い、このリポジトリが追加ソフトウェアを管理します。

## 使い方

curlsh自体はマシンにインストールしません。毎回`curl | bash`で最新リリースを取得して実行します。

```bash
curl -fsSL https://github.com/sugipamo/curlsh/releases/latest/download/install.sh | sudo bash
```

初回は`gum`のチェックリストで部品を選びます。`gum`がない場合は、署名付きの
Charm APTリポジトリからインストールします。選んだ内容は`/etc/curlsh/config.yaml`に
保存してから適用します。2回目以降に同じコマンドを実行すると、保存した宣言に従って
インストールと更新を行います。

| 操作 | コマンド（`curl ... \| sudo bash -s --`に続けて指定） |
|---|---|
| 保存した宣言を適用・更新 | 引数なし |
| 部品を選び直す | `configure` |
| 宣言ファイルを使う | `--config ./curlsh.yaml`または`--config https://...` |
| 部品を直接指定 | `--components base,tailscale --platform vm` |
| 変更せずに内容だけ確認 | `--dry-run` |
| 確認を出さない | `--non-interactive` |

### 宣言ファイル

```yaml
# /etc/curlsh/config.yaml
platform: vm          # auto|lxc|vm|baremetal。省略するとauto
components:
  - base
  - github_cli
  - tailscale
  - codex
```

このファイルを編集して再実行すると、その内容がマシンに反映されます。
`--config`で渡したファイルやhttps URLの内容は、検証後に`/etc/curlsh/config.yaml`へ
コピーします。そのため、次回からは引数なしで同じ宣言を使えます。
宣言から外した部品はアンインストールしません。管理対象から外れるだけです。

前回適用したリリースタグと日時は`/var/lib/curlsh/state`に記録します。これは表示用で、
削除しても動作に影響しません。

### 版の選び方

既定では最新リリースを使います。リリースに添付した`install.sh`には、そのリリースの
タグが埋め込まれています。ロールも同じタグのアーカイブから取得します。
Cloud-Initなどで結果を固定したい場合は、タグ付きのURLを使います。

```bash
curl -fsSL https://github.com/sugipamo/curlsh/releases/download/v0.2.0/install.sh |
  sudo bash -s -- --non-interactive --config https://example.com/web-vm.yaml
```

`--ref vX.Y.Z`を指定すると、そのタグのロールを使います。forkを使う場合は
`--repo OWNER/REPOSITORY`を指定してください。

### リポジトリから実行

チェックアウトした`install.sh`を実行すると、ダウンロードせずにそのチェックアウトの
ロールを使います。

```bash
git clone https://github.com/sugipamo/curlsh.git
cd curlsh
sudo ./install.sh
```

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

Dockerは初版ではLXC対象外です。`platform: auto`は仮想化環境を推定しますが、
判定が違う場合は宣言ファイルの`platform`で指定できます。

## Proxmoxでの流れ

VMはDebian cloud imageからCloneし、Cloud-Initでユーザー、SSH公開鍵、hostname、
DHCPを設定した後にcurlshを実行します。LXCはProxmox標準のDebianテンプレートで
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
./tests/test-install.sh
ansible-playbook -i localhost, -c local playbook.yml \
  -e bootstrap_platform=vm --syntax-check
```

Ansible roleは繰り返し実行できます。宣言した部品のroleだけが動きます。
`vX.Y.Z`タグをpushすると、Releaseワークフローがタグを埋め込んだ`install.sh`を
リリースに添付します。
パッケージの更新はAPTの現在の候補版に従うため、実行時期によって結果が変わります。
