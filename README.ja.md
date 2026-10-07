# curlsh

[English](README.md)

Debian 12/13 に開発用ツールを `curl | bash` 一発でセットアップします。
VM、Proxmox の LXC、物理マシンで使えます。

```bash
curl -fsSL https://github.com/sugipamo/curlsh/releases/latest/download/install.sh | sudo bash
```

- **インストール不要**: curlsh 自体はマシンに残りません。毎回最新リリースを取得するので、
  常に最新版を使えます。
- **インストールと更新が同じコマンド**: 選んだ内容は `/etc/curlsh/config.yaml` に保存されます。
  もう一度実行すると更新されます。
- **何度実行しても安全**: Ansible の role が、足りないものや古いものだけを変更します。

## はじめかた

1. 対象マシンで上のコマンドを実行します。
2. チェックリストから部品を選びます（スペースで選択、Enter で決定）。
3. 確認すると、選択内容を保存してセットアップします。

あとで更新するときは、同じコマンドをもう一度実行するだけです。

## コマンド

`curl ... | sudo bash -s --` の後ろにオプションを付けます。

| やりたいこと | オプション |
|---|---|
| 保存した内容を適用・更新 | *（なし）* |
| 部品を選び直す | `configure` |
| 設定ファイルや URL を使う | `--config ./curlsh.yaml` / `--config https://...` |
| コマンドラインで部品を指定 | `--components base,tailscale --platform vm` |
| 何も変更せず内容だけ確認 | `--dry-run` |
| 確認を出さない（自動化向け） | `--non-interactive` |

例:

```bash
curl -fsSL https://github.com/sugipamo/curlsh/releases/latest/download/install.sh |
  sudo bash -s -- --components base,github_cli,codex --platform vm
```

## 部品

| 名前 | 内容 | 対象 |
|---|---|---|
| `base` | 証明書、curl、git、jq、SSH クライアント | すべて |
| `github_cli` | 公式 APT リポジトリの `gh` | すべて |
| `tailscale` | Tailscale stable 版と `tailscaled` の有効化 | すべて |
| `codex` | 固定版 Codex CLI と、最小 PATH 用の `/usr/bin/codex` | すべて |
| `docker` | 公式リポジトリの Docker Engine と Compose | VM・物理マシン |
| `nodejs` | Debian の Node.js と npm | すべて |
| `devtools` | コンパイラ、make、ripgrep など | すべて |
| `qemu_guest_agent` | QEMU guest agent | VM のみ |

## 設定ファイル

```yaml
# /etc/curlsh/config.yaml
platform: vm      # auto | lxc | vm | baremetal（省略時は auto）
components:
  - base
  - github_cli
  - tailscale
  - codex
```

- このファイルを編集して再実行すると、変更が反映されます。
- `--config` にはファイルか `https://` の URL を指定できます。内容を検証してから
  `/etc/curlsh/config.yaml` にコピーするので、次回からは引数なしで使えます。
- 一覧から外した部品はアンインストール**しません**。管理対象から外れるだけです。
- `platform: auto` は自動判定です。判定が違う場合は自分で指定してください。
- `/var/lib/curlsh/state` には前回適用したリリースを記録します。表示用なので消しても問題ありません。

## バージョン

既定では最新の GitHub リリースを使います。Cloud-Init などで版を固定したい場合は、
タグ付きリリースの `install.sh` を取得します。

```bash
curl -fsSL https://github.com/sugipamo/curlsh/releases/download/v0.2.1/install.sh |
  sudo bash -s -- --non-interactive
```

ほかに、`--ref vX.Y.Z` で別リリースの role を、`--repo OWNER/NAME` でフォークを使えます。

## Proxmox と Cloud-Init

[docs/proxmox.md](docs/proxmox.md)（英語）と
[Cloud-Init の例](examples/cloud-init-user-data.yml)を参照してください。

## セキュリティ上の注意

- `curl | bash` は実行のたびにこの GitHub リポジトリを信頼します。毎回同じ結果が必要なら
  タグで固定してください。
- Tailscale、Codex、GitHub へのログインは各マシンで行ってください。認証キー、API キー、
  `~/.codex/auth.json` はこのリポジトリに保存しません。
- Codex は [OpenAI 公式インストーラー](https://learn.chatgpt.com/docs/codex/cli)で、
  `vars/versions.yml` に固定したバージョンを入れます。
- チェックリストには `gum` を使います。入っていない場合は、署名付きの Charm APT
  リポジトリを追加してインストールします。

## 開発

```bash
./tests/test-install.sh
ansible-playbook -i localhost, -c local playbook.yml \
  -e bootstrap_platform=vm --syntax-check
sudo ./install.sh     # このチェックアウトの role で実行
```

リリース: `vX.Y.Z` タグを push すると、Release ワークフローがタグを書き込んだ
`install.sh` を GitHub リリースに添付します。
