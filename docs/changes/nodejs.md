## nodejs - Debian Node.js and npm

Packages: `nodejs`, `npm`.

Sources: the host's configured APT sources; no NodeSource or other repository is added.

Writes: package-managed files and APT indexes/cache (3600-second cache validity).
No application or shell-profile configuration is directly managed by this role.

Services: none explicitly managed by this role.

Conflicts: other Node installations on PATH are not removed or reconciled.

Rerun: ensures packages are present; does not force upgrades or select a Node major version.

Uncertain: versions and dependencies follow the host's APT candidates, not upstream latest.

Does not run: no npm install, project setup, global npm packages or version-manager setup.

Implementation: [nodejs role](../../roles/nodejs/tasks/main.yml).
