## codex - Codex CLI

Packages: no direct APT package. Shared repository prerequisites also apply.

Sources: https://chatgpt.com/codex/install.sh, executed with the release version pinned in
vars/versions.yml. The installer fetches additional upstream artifacts. The current pin
is displayed separately in the plan. The installer itself is NOT pinned or checksummed.

Writes: /var/tmp/machine-bootstrap-codex-install.sh (retained), /usr/local/bin/codex,
installer-managed files under /usr/local/lib/codex, and the /usr/bin/codex symlink pointing
to /usr/local/bin/codex. Additional upstream installer side effects are not exhaustively predicted.

Services: none explicitly managed by this role.

Conflicts: preflight rejects unsupported architectures and an existing /usr/bin/codex
unless it is the expected symlink. This does not protect unrelated installations at
/usr/local/bin/codex or /usr/local/lib/codex; inspect those paths before approving replacement.

Rerun: runs the installer if /usr/local/bin/codex --version differs from the pin or fails.
A newer installed version can therefore be DOWNGRADED to the pin. The symlink is ensured
and minimal-PATH execution is verified even if the pinned version is already installed.

Uncertain: the release version is pinned, but upstream installer contents, downloads and
their side effects can change. A tool found elsewhere on PATH may shadow this installation.

Does not run: no login, credential inspection, user-profile modification by curlsh,
Node.js/npm installation, or automatic selection of the latest upstream release.

Implementation: [codex role](../../roles/codex/tasks/main.yml),
[version pin](../../vars/versions.yml), [shared dependency](../../roles/codex/meta/main.yml).
