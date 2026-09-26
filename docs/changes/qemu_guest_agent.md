## qemu_guest_agent - QEMU guest agent

Packages: `qemu-guest-agent`.

Sources: the host's configured APT sources; no new source is added.

Writes: package-managed files, APT indexes/cache (3600-second cache validity) and service state.

Services: `qemu-guest-agent` is enabled and started.

Conflicts: only VM is supported; preflight requires systemd and
/dev/virtio-ports/org.qemu.guest_agent.0. Missing channel stops before installation.

Rerun: ensures the package and active service; does not force upgrades or change the host VM.

Uncertain: versions/dependencies follow APT. Once running, the guest agent can receive
management requests from the virtualization host; host policy is outside this recipe.

Does not run: no Proxmox qm command, VM cold-start, host configuration or VM backup request.

Implementation: [qemu_guest_agent role](../../roles/qemu_guest_agent/tasks/main.yml),
[preflight](../../lib/diagnostics.sh).
