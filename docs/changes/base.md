## base - Basic tools

Packages: `ca-certificates`, `curl`, `git`, `jq`, `openssh-client`.

Sources: the host's configured APT sources; no new source is added.

Writes: package-managed files and APT indexes/cache (3600-second cache validity).
No additional configuration file is directly managed by this role.

Services: none explicitly managed by this role.

Conflicts: APT errors stop installation; existing tool configuration is not deliberately reset.

Rerun: ensures packages are present; existing packages are not unconditionally upgraded.

Uncertain: missing package versions and dependencies follow current APT candidates.

Does not run: no Git identity setup, SSH server installation or SSH key generation.

Implementation: [base role](../../roles/base/tasks/main.yml).
