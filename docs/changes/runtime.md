## Execution environment (all selections)

Packages: `ansible-core` (only if ansible-playbook is unavailable), `python3-apt` (if missing).

Sources: the host's configured APT sources. A standalone bootstrap also downloads the
matching fixed-tag repository archive from GitHub into a temporary directory, removed on exit.
A local checkout uses its own files, including local edits; --ref does not replace them.

Writes: after approval, APT may refresh /var/lib/apt/lists and write package/cache/lock data.
Ansible may create temporary execution files. No curlsh executable, selected profile,
configuration database or selection history is installed or saved.

Services: none explicitly managed by the execution environment.

Conflicts: APT locks, broken package state or unavailable sources can stop installation.
curlsh does not automatically repair them. Existing Ansible on PATH is used, not replaced.

Rerun: missing execution dependencies are installed with --no-install-recommends;
already available dependencies are not intentionally upgraded. Selected roles run again.

Uncertain: APT dependency resolution, maintainer scripts, downloads, disk usage and
package/service side effects depend on the host and current repositories. Role APT tasks
use the host's default recommendation policy. This is a scope description, not an exact diff
or a rollback transaction; completed changes remain if a later task fails.

Does not run: no full-system upgrade, automatic rollback/removal, authentication, host
Proxmox configuration, curlsh self-install or self-update. The menu uses existing gum if
available, otherwise Bash text input; no gum installation or Charm repository is added.
Dry-run does not run APT updates, Ansible, vendor connectivity checks or installed-tool
version commands. A standalone dry-run still downloads its own source into temporary storage.
Normal status/menu/verification probes may execute installed tools with version flags.

Approval: interactive selection, plan display and preflight precede a single explicit
confirmation. Declining, EOF or Ctrl-C before approval does not reach the install phase.
--non-interactive with --components authorizes installation without a prompt; it still
prints the same plan and runs preflight. Preflight may make read-only HTTPS requests.

Implementation: [bootstrap.sh](../../bootstrap.sh), [playbook.yml](../../playbook.yml),
[diagnostics](../../lib/diagnostics.sh), [plan renderer](../../lib/plan.sh), [menu](../../lib/menu.sh).
