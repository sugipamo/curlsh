## github_cli - GitHub CLI

Packages: `gh`. Shared repository prerequisites also apply.

Sources: https://cli.github.com/packages (stable main); signing key downloaded from
https://cli.github.com/packages/githubcli-archive-keyring.gpg.

Writes: /etc/apt/keyrings/githubcli-archive-keyring.gpg,
/etc/apt/sources.list.d/github-cli.list, package-managed files and APT indexes/cache.

Services: none explicitly managed by this role.

Conflicts: an existing signing-key file may be replaced. The APT source is ensured present;
other source files are not reconciled, so duplicate/incompatible definitions may cause errors.

Rerun: ensures the source and package are present; does not force an existing gh upgrade.

Uncertain: the unpinned signing key, APT candidate, package dependencies and maintainer scripts.

Does not run: no gh auth login, credential inspection, Git credential-helper or identity setup.

Implementation: [github_cli role](../../roles/github_cli/tasks/main.yml),
[shared dependency](../../roles/github_cli/meta/main.yml).
