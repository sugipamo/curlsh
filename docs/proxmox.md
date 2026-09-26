# Proxmoxへの適用

## VM

1. Debian公式cloud imageをProxmoxへ取り込み、Cloud-Initドライブ付きVMテンプレートを作成。
2. テンプレートをCloneし、Cloud-Initで一意のhostname、SSH公開鍵、DHCPを指定。
3. `vmbr1`と配置先OPNsenseのLANネットワークへ接続して起動。
4. SSHで入り、`bootstrap.sh --non-interactive --platform vm`を実行。
5. Proxmox側でもVMのQEMU guest agentを有効化。

```bash
sudo ./bootstrap.sh --non-interactive --platform vm \
  --components base,github_cli,tailscale,codex,qemu_guest_agent
```

Cloud-Initの`runcmd`で実行する場合は、タグ固定のbootstrapを取得してください。
ネットワーク疎通が必要なので、Cloud-Initの初回実行ログを確認します。
実行例は[Cloud-Init user-data](../examples/cloud-init-user-data.yml)を参照してください。
Tailnet登録用キーやCodex認証情報をCloud-Init user-dataへ埋め込みません。

## LXC

1. Proxmox標準Debianテンプレートからunprivileged CTを作成。
2. Bridge `vmbr1`、IPv4 DHCP、配置先OPNsenseをDNSに設定。
3. Tailscale用に`/dev/net/tun`をDevice Passthroughで追加して起動。
4. CT内でbootstrapを実行。

```bash
./bootstrap.sh --non-interactive --platform lxc \
  --components base,github_cli,tailscale,codex
```

TUNはProxmox側の設定です。bootstrapはデバイスがない場合、変更前に中断します。
`tailscale up --ssh --advertise-tags=tag:agent`はCTごとに実行してください。

## 作成後の確認

```bash
codex --version
tailscale status
gh --version
```

ヘッドレスマシンのCodexサインインは`codex login --device-auth`を利用できます。
認証状態は`codex login status`で確認します。トークンやauth.jsonの内容は共有しないでください。
