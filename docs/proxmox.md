# Using curlsh on Proxmox

## VM

1. Import the official Debian cloud image into Proxmox and make a VM template
   with a Cloud-Init drive.
2. Clone the template. In Cloud-Init, set a unique hostname, your SSH public key
   and DHCP.
3. Connect it to `vmbr1` and the target OPNsense LAN, then start it.
4. SSH in and run curlsh.
5. Enable the QEMU guest agent for the VM on the Proxmox side too.

```bash
curl -fsSL https://github.com/sugipamo/curlsh/releases/latest/download/install.sh |
  sudo bash -s -- --platform vm \
  --components base,github_cli,tailscale,codex,qemu_guest_agent
```

### With Cloud-Init

Place the config with `write_files`, then run a pinned `install.sh` from
`runcmd`. See the [Cloud-Init example](../examples/cloud-init-user-data.yml).
You can also pass a config URL with `--config https://...`.

curlsh needs network access, so check the Cloud-Init log after the first boot.
Do not put Tailscale auth keys or Codex credentials in user-data.

## LXC

1. Create an unprivileged container from the standard Proxmox Debian template.
2. Use bridge `vmbr1`, IPv4 DHCP, and the target OPNsense as DNS.
3. For Tailscale, add `/dev/net/tun` with Device Passthrough, then start it.
4. Run curlsh inside the container.

```bash
curl -fsSL https://github.com/sugipamo/curlsh/releases/latest/download/install.sh |
  sudo bash -s -- --platform lxc --components base,github_cli,tailscale,codex
```

TUN is configured on the Proxmox side. If the device is missing, curlsh stops
before changing anything. Run `tailscale up --ssh --advertise-tags=tag:agent`
in each container.

Docker is not supported on LXC.

## Updating

Run the same command with no arguments on each machine. It applies
`/etc/curlsh/config.yaml` with the latest release.

```bash
curl -fsSL https://github.com/sugipamo/curlsh/releases/latest/download/install.sh | sudo bash
```

## Checking the result

```bash
codex --version
tailscale status
gh --version
```

On headless machines, sign in to Codex with `codex login --device-auth` and
check with `codex login status`. Never share tokens or the contents of
`auth.json`.
