## Shared repository prerequisites

Packages: `ca-certificates`, `curl`.

Sources: the host's configured APT sources. Used by github_cli, tailscale, codex and docker.

Writes: /etc/apt/keyrings (directory, mode 0755); APT package data and indexes
(refreshed when the cache is older than 3600 seconds).

Services: none explicitly managed by this role.

Conflicts: existing directory permissions may be corrected; APT failures stop the role.

Rerun: ensures packages are present and the directory exists; no unconditional package upgrade.

Uncertain: actual versions, dependencies and package-maintainer side effects follow APT.

Does not run: no vendor authentication, no removal of existing repository definitions.

Implementation: [repository_prerequisites role](../../roles/repository_prerequisites/tasks/main.yml).
