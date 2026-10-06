# curlsh

[日本語](README.ja.md)

Set up development tools on Debian 12/13 with a single `curl | bash`.
Works on VMs, Proxmox LXC containers and physical machines.

```bash
curl -fsSL https://github.com/sugipamo/curlsh/releases/latest/download/install.sh | sudo bash
```

- **Nothing to install.** curlsh itself never stays on the machine. Every run
  downloads the latest release, so you always use the newest version.
- **Install and update are the same command.** Your choice is saved in
  `/etc/curlsh/config.yaml`. Run the command again to apply updates.
- **Safe to re-run.** Ansible roles only change what is missing or outdated.

## Quick start

1. Run the command above on the target machine.
2. Pick components from the checklist (Space to select, Enter to continue).
3. Confirm. curlsh saves your choice and sets up the machine.

To update later, run the same command again.

## Commands

Add options after `curl ... | sudo bash -s --`:

| What you want | Options |
|---|---|
| Apply or update the saved choice | *(none)* |
| Choose components again | `configure` |
| Use a config file or URL | `--config ./curlsh.yaml` / `--config https://...` |
| Choose components on the command line | `--components base,tailscale --platform vm` |
| Show what would happen, change nothing | `--dry-run` |
| Never prompt (for automation) | `--non-interactive` |

Example:

```bash
curl -fsSL https://github.com/sugipamo/curlsh/releases/latest/download/install.sh |
  sudo bash -s -- --components base,github_cli,codex --platform vm
```

## Components

| Name | What it installs | Platforms |
|---|---|---|
| `base` | CA certificates, curl, git, jq, SSH client | all |
| `github_cli` | `gh` from the official APT repository | all |
| `tailscale` | Tailscale stable, with `tailscaled` enabled | all |
| `codex` | Pinned Codex CLI, plus `/usr/bin/codex` for minimal PATHs | all |
| `docker` | Docker Engine and Compose from the official repository | VM, physical |
| `nodejs` | Node.js and npm from Debian | all |
| `devtools` | Compiler, make, ripgrep and similar | all |
| `qemu_guest_agent` | QEMU guest agent | VM only |

## Config file

```yaml
# /etc/curlsh/config.yaml
platform: vm      # auto | lxc | vm | baremetal (default: auto)
components:
  - base
  - github_cli
  - tailscale
  - codex
```

- Edit this file and run curlsh again to apply the change.
- `--config` accepts a local file or an `https://` URL. The file is checked,
  then copied to `/etc/curlsh/config.yaml` so later runs need no arguments.
- Removing a component does **not** uninstall it. curlsh just stops managing it.
- `platform: auto` detects the platform. Set it yourself if detection is wrong.
- `/var/lib/curlsh/state` records the last applied release. It is only used
  for display and can be deleted.

## Versions

By default curlsh uses the latest GitHub release. To pin a version (for
example in Cloud-Init), download `install.sh` from a tagged release:

```bash
curl -fsSL https://github.com/sugipamo/curlsh/releases/download/v0.2.0/install.sh |
  sudo bash -s -- --non-interactive
```

Other options: `--ref vX.Y.Z` uses roles from another release, and
`--repo OWNER/NAME` uses a fork.

## Proxmox and Cloud-Init

See [docs/proxmox.md](docs/proxmox.md) and the
[Cloud-Init example](examples/cloud-init-user-data.yml).

## Security notes

- `curl | bash` trusts this GitHub repository each time it runs. Pin a tag if
  you need the same result every time.
- Sign in to Tailscale, Codex and GitHub on each machine yourself. Auth keys,
  API keys and `~/.codex/auth.json` are never stored in this repository.
- Codex is installed with the
  [official OpenAI installer](https://learn.chatgpt.com/docs/codex/cli) at the
  version pinned in `vars/versions.yml`.
- The checklist uses `gum`. If it is missing, curlsh adds the signed Charm APT
  repository to install it.

## Development

```bash
./tests/test-install.sh
ansible-playbook -i localhost, -c local playbook.yml \
  -e bootstrap_platform=vm --syntax-check
sudo ./install.sh     # runs the roles from this checkout
```

Releasing: push a `vX.Y.Z` tag. The Release workflow writes the tag into
`install.sh` and attaches it to the GitHub release.
