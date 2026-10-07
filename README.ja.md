# curlsh

[English](README.md)

Debian 12/13 に、設定ファイル1つと `curl | bash` で開発用ツールをセットアップします。
VM、Proxmox の LXC、物理マシンで使えます。

```bash
curl -fsSL https://github.com/sugipamo/curlsh/releases/latest/download/install.sh |
  sudo bash -s -- --config https://example.com/my-machine.yaml
```

- **何も残さない**: curlsh 本体、設定ファイル、実行記録のどれもマシンに残しません。
  必要なのは `bash` と `curl` だけです。
- **設定ファイルが正**: 設定はリポジトリや gist などで管理し、毎回渡します。
- **毎回マシンを確認する**: 足りないものはインストールし、入っているものは最新版に
  上げます。更新したいときはもう一度実行するだけです。

## 設定ファイル

```yaml
platform: vm      # auto | lxc | vm | baremetal（省略時は auto）
components:
  - base
  - github_cli
  - tailscale
  - codex
```

`components: [base, codex]` の形でも書けます。使えるキーは `platform` と `components`
だけで、それ以外はエラーになります。[examples](examples/) も参照してください。

`--config` にはファイルか `https://` の URL を指定します。

## 事前に確認する

`--check` を付けると、何も変更せずに変更予定だけを表示します。

```bash
curl -fsSL https://github.com/sugipamo/curlsh/releases/latest/download/install.sh |
  bash -s -- --check --config https://example.com/my-machine.yaml
```

```
Packages
  ok             git 1:2.47.3-0+deb13u1
  will upgrade   gh 2.101.0 -> 2.102.0
Codex
  will install   codex 0.160.1
Check: 2 change(s) needed
```

## 部品

| 名前 | 内容 | 対象 |
|---|---|---|
| `base` | 証明書、curl、git、jq、SSH クライアント | すべて |
| `github_cli` | 公式 APT リポジトリの `gh` | すべて |
| `tailscale` | Tailscale stable 版と `tailscaled` の有効化 | すべて |
| `codex` | 最新の Codex CLI と、最小 PATH 用の `/usr/bin/codex` | すべて |
| `docker` | 公式リポジトリの Docker Engine と Compose | VM・物理マシン |
| `nodejs` | Debian の Node.js と npm | すべて |
| `devtools` | コンパイラ、make、ripgrep など | すべて |
| `qemu_guest_agent` | QEMU guest agent | VM のみ |

外部リポジトリを使う部品（`github_cli`、`tailscale`、`docker`）は、APT で更新できるよう
署名鍵と取得元の設定を追加します。

設定から外した部品はアンインストール**しません**。管理対象から外れるだけです。

## バージョン

既定では最新の curlsh リリースを使います。Cloud-Init などで固定したい場合は、
タグ付きの URL を使います。

```bash
curl -fsSL https://github.com/sugipamo/curlsh/releases/download/v0.3.0/install.sh |
  sudo bash -s -- --config https://example.com/my-machine.yaml
```

固定されるのは curlsh の動作だけです。パッケージと Codex は常に最新版に上がります。

## Proxmox と Cloud-Init

[docs/proxmox.md](docs/proxmox.md)（英語）と
[Cloud-Init の例](examples/cloud-init-user-data.yml)を参照してください。

## セキュリティ上の注意

- `curl | bash` は、実行のたびにこの GitHub リポジトリと設定ファイルの URL を信頼します。
  curlsh 自体を固定したい場合はタグを指定してください。
- Tailscale、Codex、GitHub へのログインは各マシンで行ってください。認証キーや
  `~/.codex/auth.json` を設定ファイルに入れないでください。
- Codex は [OpenAI 公式インストーラー](https://learn.chatgpt.com/docs/codex/cli)で入れます。

## 開発

```bash
./tests/test-install.sh                                  # shellcheck が必要
sudo ./install.sh --config tests/smoke.yaml              # Debian のテスト用マシンで
```

CI は最小構成の Debian 12 と 13 に `tests/smoke.yaml` を2回適用し、2回目に変更がないことを
確認します。

リリース: `vX.Y.Z` タグを push するか、Actions 画面から Release ワークフローを新しい
タグ名で実行します。タグを書き込んだ `install.sh` が GitHub リリースに添付されます。
