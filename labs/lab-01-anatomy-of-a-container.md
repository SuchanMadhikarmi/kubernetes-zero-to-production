# Lab 01 - The Anatomy of a Container

## Objective

Prove that a container is a constrained Linux process by observing, hands-on, both halves of the story:

- **Namespaces** isolate what a process sees (it believes it is PID 1 and alone on the machine).
- **cgroups** limit what a process can use (memory limit kills the process when exceeded).

## Prerequisites

- Lesson 01 - The Anatomy of a Container.
- Docker installed and running on a Linux machine (Ubuntu recommended).
- A terminal.

### Installing Docker

```bash
# Ubuntu/Debian
sudo apt-get update
sudo apt-get install -y docker.io
sudo usermod -aG docker $USER
# Log out and back in for group changes to take effect

# Verify
docker --version
```

## Target Environment

Local Linux host with Docker. The same concepts map directly onto any Kubernetes cluster via the Container Runtime Interface.

## Steps

### 1. Inspect the host process tree

```bash
ps aux | head -n 10
```

Expected: normal host processes, with `systemd` (or `init`) as PID 1. Note the number of processes and the PID 1.

### 2. Start an isolated container

```bash
docker run -it --memory="512m" --cpus="1" ubuntu:22.04 /bin/bash
```

This creates a cgroup with a 512MB RAM limit and a one-CPU limit, then opens a shell inside a fresh set of namespaces.

### 3. Confirm the PID namespace isolation

```bash
ps aux
```

Expected: the container's shell appears as `/bin/bash` with **PID 1**. The host's `systemd` and other processes are invisible. This is the PID namespace in action.

You can also confirm you are not root's host session unexpectedly limited by checking the hostname view:

```bash
hostname
cat /proc/self/cgroup
```

### 4. Confirm the network namespace

```bash
ip addr show
```

The container sees its own network interface with its own IP, not the host's full set of interfaces.

### 5. Test reading the cgroup memory limit

```bash
cat /sys/fs/cgroup/memory/memory.limit_in_bytes 2>/dev/null
```

Look for the value corresponding to 512MB (`536870912`). If your system uses cgroup v2, inspect the equivalent v2 file instead.

### 6. Demonstrate OOM behavior (Optional, Mini Project)

Run a container with a hard memory limit and force it to exceed the limit:

```bash
docker run -it --memory="100m" ubuntu:22.04 /bin/bash
```

Inside the container, allocate memory rapidly:

```bash
# repeat allocation until the process is killed
yes 123456789 | md5sum
```

Expected: the container exits with code 137 (OOM kill) because it exceeded its cgroup memory limit.

Verify with:

```bash
docker ps -a
```

The stopped container is shown with a high exit code.

## Verification

- The containerized `ps aux` shows PID 1 as the shell and hides the host's processes -> namespace isolation confirmed.
- The memory-limited container is killed by the kernel when it exceeds the limit -> cgroup limitation confirmed.

## Cleanup

```bash
exit          # inside the container shell
docker ps -a  # list any stopped containers from this lab
# Remove them if you want to free resources
docker rm <container-id>
```

## Expected Output Snapshot

```text
# Inside a disconnected container
PID   USER  TIME  COMMAND
1     root  0:00  /bin/bash
```

Note: the exact `ps` columns vary by image. The key observation is the container's own process tree with a low PID 1, and the absence of host processes.

## Related

- Lesson file: [lesson-01-anatomy-of-a-container.md](../docs/01-fundamentals/lesson-01-anatomy-of-a-container.md)