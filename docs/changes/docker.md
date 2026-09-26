## docker - Docker Engine and Compose

Packages: `docker-ce`, `docker-ce-cli`, `containerd.io`, `docker-buildx-plugin`, `docker-compose-plugin`.
Shared repository prerequisites also apply.

Sources: https://download.docker.com/linux/debian (stable, host codename/architecture);
signing key from https://download.docker.com/linux/debian/gpg.

Writes: /etc/apt/keyrings/docker.asc, /etc/apt/sources.list.d/docker.list,
package-managed files and APT indexes/cache. Daemons maintain their own data (normally
/var/lib/docker and /var/lib/containerd) and networking rules according to host configuration.

Services: `docker` is enabled and started. Package scripts/systemd dependencies can also
start containerd and related units; the role does not enumerate every package side effect.

Conflicts: LXC is rejected. Preflight requires systemd and rejects docker.io,
docker-compose, docker-doc, podman-docker, containerd and runc. Nothing is removed automatically.
Existing key files may be replaced; other source definitions are not reconciled.

Rerun: ensures packages/source/service; does not force package upgrades or reset daemon
configuration. Starting an existing daemon can restart containers according to their policies.

Uncertain: APT versions/dependencies, upstream key contents, network changes and effects
on existing workloads depend on packages and existing Docker configuration.

Does not run: no docker run, image pull, docker-group membership change, data migration,
container cleanup or removal of conflicting packages. hello-world is only suggested.

Implementation: [docker role](../../roles/docker/tasks/main.yml),
[shared dependency](../../roles/docker/meta/main.yml), [preflight](../../lib/diagnostics.sh).
