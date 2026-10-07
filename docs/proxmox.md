# Using curlsh on Proxmox

Keep one config per kind of machine, for example in a Git repository, and pass
its URL with `--config`. Starting points: [vm.yaml](../examples/vm.yaml) and
[lxc.yaml](../examples/lxc.yaml).

## VM

1. Import the official Debian cloud image into Proxmox and make a VM template
   with a Cloud-Init drive.
2. Clone the template. In Cloud-Init, set a unique hostname, your SSH public key
   and DHCP.
3. Connect it to `vmbr1` and the target OPNsense LAN, then start it.
4. SSH in and run curlsh with your VM config.
5. Enable the QEMU guest agent for the VM on the Proxmox side too.

```bash
curl -fsSL https://github.com/sugipamo/curlsh/releases/latest/download/install.sh |
  sudo bash -s -- --config https://example.com/vm.yaml
```

### With Cloud-Init

Run a pinned `install.sh` from `runcmd`. See the
[Cloud-Init example](../examples/cloud-init-user-data.yml). curlsh needs
network access, so check the Cloud-Init log after the first boot. Do not put
Tailscale auth keys or Codex credentials in user-data.

## LXC

1. Create an unprivileged container from the standard Proxmox Debian template.
2. Use bridge `vmbr1`, IPv4 DHCP, and the target OPNsense as DNS.
3. For Tailscale, add `/dev/net/tun` with Device Passthrough, then start it.
4. Run curlsh inside the container with your LXC config.

```bash
curl -fsSL https://github.com/sugipamo/curlsh/releases/latest/download/install.sh |
  sudo bash -s -- --config https://example.com/lxc.yaml
```

TUN is configured on the Proxmox side. If the device is missing, curlsh stops
before changing anything. Run `tailscale up --ssh --advertise-tags=tag:agent`
in each container. Docker is not supported on LXC.

## Updating

Run the same command again. curlsh checks the machine against the config and
upgrades everything to the latest version. Add `--check` first to see what
would change.

## Checking the result

```bash
codex --version
tailscale status
gh --version
```

On headless machines, sign in to Codex with `codex login --device-auth` and
check with `codex login status`. Never share tokens or the contents of
`auth.json`.
