## devtools - Development tools

Packages: `build-essential`, `git`, `make`, `pkg-config`, `ripgrep`, `unzip`.

Sources: the host's configured APT sources; no new source is added.

Writes: package-managed files and APT indexes/cache (3600-second cache validity).
No project files or compiler configuration are directly managed by this role.

Services: none explicitly managed by this role.

Conflicts: APT errors stop the role; tools installed elsewhere are not removed.

Rerun: ensures packages are present; does not force upgrades or run a build.

Uncertain: compiler/tool versions and dependencies follow current APT candidates.

Does not run: no compilation, repository cloning, Git identity setup or project dependencies.

Implementation: [devtools role](../../roles/devtools/tasks/main.yml).
