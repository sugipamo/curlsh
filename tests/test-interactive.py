"""Exercise the real bootstrap under a PTY with an isolated, entirely spied PATH."""

import errno
import os
import pty
import select
import signal
import subprocess
import time


fixture = os.environ["CURLSH_TEST_FIXTURE"]
entrypoint = f"{fixture}/project/bootstrap.sh"
select_prompt = "or leave blank to cancel: "
approve_prompt = "Type yes to begin system changes; anything else cancels: "


def run_case(name, replies, expected=1, gum=False, approved=False, **overrides):
    env = dict(os.environ, **overrides)
    env["PATH"] = f"{fixture}/bin"
    if gum:
        env["PATH"] = f"{fixture}/gum-bin:" + env["PATH"]
    marker = f"{fixture}/{name}.mutation"
    env["CURLSH_TEST_MUTATIONS"] = marker
    pid, terminal = pty.fork()
    if pid == 0:
        os.execve("/bin/bash", ["bash", entrypoint, "--platform", "lxc"], env)
    transcript = b""
    pending = list(replies)
    finished = False
    try:
        deadline = time.monotonic() + 20
        while time.monotonic() < deadline:
            ready, _, _ = select.select([terminal], [], [], 0.1)
            if ready:
                try:
                    chunk = os.read(terminal, 65536)
                except OSError as error:
                    if error.errno != errno.EIO:
                        raise
                    chunk = b""
                transcript += chunk
            if pending and pending[0][0].encode() in transcript:
                _, reply = pending.pop(0)
                os.write(terminal, reply)
            child, status = os.waitpid(pid, os.WNOHANG)
            if child:
                finished = True
                result = os.waitstatus_to_exitcode(status)
                # Drain output written just before the process exited.
                while select.select([terminal], [], [], 0)[0]:
                    try:
                        chunk = os.read(terminal, 65536)
                    except OSError as error:
                        if error.errno != errno.EIO:
                            raise
                        break
                    if not chunk:
                        break
                    transcript += chunk
                break
        else:
            raise AssertionError(f"{name}: timeout: {transcript.decode(errors='replace')}")
    finally:
        if not finished:
            os.kill(pid, signal.SIGKILL)
            os.waitpid(pid, 0)
        os.close(terminal)
    output = transcript.decode(errors="replace")
    assert result == expected, (name, result, output)
    assert not pending, (name, "did not reach expected prompt", output)
    assert os.path.exists(marker) == approved, (name, "unexpected install boundary", output)
    assert ("Beginning system changes." in output) == approved, (name, output)
    if approve_prompt in output:
        assert output.index("Execution plan") < output.index("Preflight (") < output.index(approve_prompt)
        assert "ansible-core" in output and "python3-apt" in output
    print(f"PTY {name}: passed")


run_case("blank-selection", [(select_prompt, b"\n")])
run_case("eof-selection", [(select_prompt, b"\x04")])
run_case("interrupt-selection", [(select_prompt, b"\x03")], expected=130)
run_case("invalid-selection", [(select_prompt, b"unknown\n")], expected=2)
run_case("empty-component", [(select_prompt, b"base,,codex\n")])
run_case("decline", [(select_prompt, b"base\n"), (approve_prompt, b"no\n")])
run_case("no-implicit-yes", [(select_prompt, b"base\n"), (approve_prompt, b"y\n")])
run_case("eof-approval", [(select_prompt, b"base\n"), (approve_prompt, b"\x04")])
run_case("interrupt-approval", [(select_prompt, b"base\n"), (approve_prompt, b"\x03")], expected=130)
run_case("failed-preflight", [(select_prompt, b"base\n")], CURLSH_TEST_SPACE="0")
run_case("gum-cancel", [], gum=True, CURLSH_TEST_GUM_CANCEL="1")
run_case("gum-decline", [(approve_prompt, b"no\n")], gum=True)
# Positive controls: approval must reach the fake APT command (which refuses to mutate).
run_case("text-approve", [(select_prompt, b"base\n"), (approve_prompt, b"yes\n")], expected=97, approved=True)
run_case("gum-approve", [(approve_prompt, b"yes\n")], gum=True, expected=97, approved=True)

# An agent can explicitly authorize the same flow without a terminal.
env = dict(os.environ, PATH=f"{fixture}/bin", CURLSH_TEST_MUTATIONS=f"{fixture}/noninteractive.mutation")
result = subprocess.run(
    ["/bin/bash", entrypoint, "--non-interactive", "--platform", "lxc", "--components", "base"],
    env=env, stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=20,
)
assert result.returncode == 97, result.stdout + result.stderr
assert "Installation authorized by --non-interactive" in result.stdout
assert os.path.exists(env["CURLSH_TEST_MUTATIONS"])
print("noninteractive explicit approval: passed")
