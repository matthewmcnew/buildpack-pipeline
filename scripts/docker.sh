#!/usr/bin/env bash
STARTUP_TIMEOUT=${STARTUP_TIMEOUT:-240}
# Ref: https://github.com/concourse/docker-image-resource/blob/master/assets/common.sh

sanitize_cgroups() {
  mkdir -p /sys/fs/cgroup
  mountpoint -q /sys/fs/cgroup || \
    mount -t tmpfs -o uid=0,gid=0,mode=0755 cgroup /sys/fs/cgroup

  mount -o remount,rw /sys/fs/cgroup

  sed -e 1d /proc/cgroups | while read sys hierarchy num enabled; do
    if [ "$enabled" != "1" ]; then
      # subsystem disabled; skip
      continue
    fi

    grouping="$(cat /proc/self/cgroup | cut -d: -f2 | grep "\\<$sys\\>")"
    if [ -z "$grouping" ]; then
      # subsystem not mounted anywhere; mount it on its own
      grouping="$sys"
    fi

    mountpoint="/sys/fs/cgroup/$grouping"

    mkdir -p "$mountpoint"

    # clear out existing mount to make sure new one is read-write
    if mountpoint -q "$mountpoint"; then
      umount "$mountpoint"
    fi

    mount -n -t cgroup -o "$grouping" cgroup "$mountpoint"

    if [ "$grouping" != "$sys" ]; then
      if [ -L "/sys/fs/cgroup/$sys" ]; then
        rm "/sys/fs/cgroup/$sys"
      fi

      ln -s "$mountpoint" "/sys/fs/cgroup/$sys"
    fi
  done

  if ! test -e /sys/fs/cgroup/systemd ; then
    mkdir /sys/fs/cgroup/systemd
    mount -t cgroup -o none,name=systemd none /sys/fs/cgroup/systemd
  fi
}

start_docker() {
  mkdir -p /var/log
  mkdir -p /var/run

  sanitize_cgroups

  # check for /proc/sys being mounted readonly, as systemd does
  if grep '/proc/sys\s\+\w\+\s\+ro,' /proc/mounts >/dev/null; then
    mount -o remount,rw /proc/sys
  fi

  local server_args=""

  for registry in $1; do
    server_args="${server_args} --insecure-registry ${registry}"
  done

  if [ -n "$2" ]; then
    server_args="${server_args} --registry-mirror=$2"
  fi

  if [ -n "$3" ]; then
    server_args="${server_args} -g=$3"
  fi

  try_start() {
    dockerd --data-root /scratch/docker ${server_args} 2>&1 &
    echo $! > /tmp/docker.pid

    trap stop_docker EXIT
    sleep 1

    echo waiting for docker to come up...
    until docker info 2>&1; do
      sleep 1
      if ! kill -0 "$(cat /tmp/docker.pid)" 2>/dev/null; then
        return 1
      fi
    done
  }

  export server_args LOG_FILE
  declare -fxr stop_docker try_start

  if ! timeout -t ${STARTUP_TIMEOUT} bash -ce 'while true; do try_start && break; done'; then
    echo Docker failed to start within ${STARTUP_TIMEOUT} seconds.
    return 1
  fi
}

stop_docker() {
  local pid=$(cat /tmp/docker.pid)
  if [ -z "$pid" ]; then
    return 0
  fi

  kill -TERM $pid
  wait $pid
}