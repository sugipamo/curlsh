# curlsh

[日本語](README.ja.md)

Set up development tools on Debian 12/13 from one config file, with a single
`curl | bash`. Works on VMs, Proxmox LXC containers and physical machines.

```bash
curl -fsSL https://github.com/sugipamo/curlsh/releases/latest/download/install.sh |
  sudo bash -s -- --config https://example.com/my-machine.yaml
```

- **Nothing left behind.** curlsh keeps no copy of itself, no saved config and
  no state on the machine. It needs only `bash` and `curl`.
- **Your config is the source of truth.** Keep it in a repository or a gist
  and pass it every time.
- **Every run checks the machine.** Missing tools are installed and installed
  ones are upgraded to the latest version. Run it again to update.

## Config

```yaml
platform: vm      # auto | lxc | vm | baremetal (default: auto)
components:
  - base
  - github_cli
  - tailscale
  - codex
```

`components: [base, codex]` also works. Only `platform` and `components`
are allowed; anything else is an error. See [examples](examples/).

`--config` takes a local file or an `https://` URL.

## Check first

`--check` shows what would change without changing anything:

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

## Components

| Name | What it installs | Platforms |
|---|---|---|
| `base` | CA certificates, curl, git, jq, SSH client | all |
| `github_cli` | `gh` from the official APT repository | all |
| `tailscale` | Tailscale stable, with `tailscaled` enabled | all |
| `codex` | Latest Codex CLI, plus `/usr/bin/codex` for minimal PATHs | all |
| `docker` | Docker Engine and Compose from the official repository | VM, physical |
| `nodejs` | Node.js and npm from Debian | all |
| `devtools` | Compiler, make, ripgrep and similar | all |
| `qemu_guest_agent` | QEMU guest agent | VM only |

Components that use a vendor repository (`github_cli`, `tailscale`,
`docker`) add its signing key and source list, since APT needs them to
update the package.

Removing a component from the config does **not** uninstall it. curlsh just
stops managing it.

## Versions

By default you get the latest curlsh release. To pin one (for example in
Cloud-Init), use a tagged URL:

```bash
curl -fsSL https://github.com/sugipamo/curlsh/releases/download/v0.3.0/install.sh |
  sudo bash -s -- --config https://example.com/my-machine.yaml
```

Pinning fixes curlsh's behaviour, not the tool versions: packages and Codex
are always upgraded to the latest.

## Proxmox and Cloud-Init

See [docs/proxmox.md](docs/proxmox.md) and the
[Cloud-Init example](examples/cloud-init-user-data.yml).

## Security notes

- `curl | bash` trusts this GitHub repository, and your config URL, each time
  it runs. Pin a tag if you need curlsh itself to stay fixed.
- Sign in to Tailscale, Codex and GitHub on each machine yourself. Never put
  auth keys or `~/.codex/auth.json` in a config.
- Codex is installed with the
  [official OpenAI installer](https://learn.chatgpt.com/docs/codex/cli).

## Development

```bash
./tests/test-install.sh                                  # needs shellcheck
sudo ./install.sh --config tests/smoke.yaml              # on a Debian test machine
```

CI applies `tests/smoke.yaml` twice on minimal Debian 12 and 13 and expects no
changes the second time.

Releasing: push a `vX.Y.Z` tag, or run the Release workflow from the Actions
tab with a new tag name. It writes the tag into `install.sh` and attaches it
to the GitHub release.
