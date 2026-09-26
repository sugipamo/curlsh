## tailscale - Tailscale

Packages: `tailscale`. Shared repository prerequisites also apply.

Sources: https://pkgs.tailscale.com/stable/debian for the host's Debian codename;
the signing key is fetched from the same source.

Writes: /usr/share/keyrings/tailscale-archive-keyring.gpg,
/etc/apt/sources.list.d/tailscale.list, package-managed files and APT indexes/cache.
Running tailscaled can create its own state and logs.

Services: `tailscaled` is enabled and started.

Conflicts: preflight requires systemd and, on LXC, /dev/net/tun. Missing prerequisites
stop before installation. An existing key may be replaced; other APT sources are not reconciled.

Rerun: ensures the source/package and active service; does not force a package upgrade or
reset existing Tailscale membership. Starting an already configured daemon can reconnect it.

Uncertain: package versions/dependencies, key contents and networking effects of the daemon
depend on upstream and any existing Tailscale configuration.

Does not run: no tailscale up/login, new tailnet enrollment, SSH enablement, tag assignment
or Proxmox device passthrough. Follow-up commands are suggestions only.

Implementation: [tailscale role](../../roles/tailscale/tasks/main.yml),
[shared dependency](../../roles/tailscale/meta/main.yml), [preflight](../../lib/diagnostics.sh).
