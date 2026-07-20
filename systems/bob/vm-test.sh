#!/usr/bin/env bash

set -euo pipefail
umask 077

if [[ $# -ne 1 ]]; then
  echo "usage: bob-vm-test /nfs/Brian/bob-backups/TIMESTAMP" >&2
  exit 2
fi

backup=$(sudo "$BOB_COREUTILS/realpath" -e -- "$1")
case "$backup/" in
  /nfs/Brian/bob-backups/*/) ;;
  *)
    echo "backup must be below /nfs/Brian/bob-backups: $backup" >&2
    exit 1
    ;;
esac

sudo "$BOB_COREUTILS/test" -e "$backup/metadata/COMPLETE" || {
  echo "backup is not ready: missing metadata/COMPLETE" >&2
  exit 1
}
source_markers=0
for marker in SOURCE-RESTARTED SOURCE-STOPPED; do
  if sudo "$BOB_COREUTILS/test" -e "$backup/metadata/$marker"; then
    source_markers=$((source_markers + 1))
  fi
done
(( source_markers == 1 )) || {
  echo "backup must contain exactly one of metadata/SOURCE-RESTARTED or metadata/SOURCE-STOPPED" >&2
  exit 1
}
sudo "$BOB_COREUTILS/test" -s "$backup/metadata/images/active-images.tar" || {
  echo "backup is missing its container image archive" >&2
  exit 1
}
read -r expected_hash _ < <(sudo "$BOB_COREUTILS/head" -n 1 "$backup/metadata/images/active-images.tar.sha256")
read -r actual_hash _ < <(sudo "$BOB_COREUTILS/sha256sum" "$backup/metadata/images/active-images.tar")
[[ $actual_hash == "$expected_hash" ]] || {
  echo "container image archive checksum failed" >&2
  exit 1
}

minimum_space=$((40 * 1024 * 1024 * 1024))
available=$(df --output=avail -B1 /tmp | tail -n 1)
(( available >= minimum_space )) || {
  echo "/tmp has less than 40 GiB free" >&2
  exit 1
}

backup_id=$(basename "$backup")
run_id=$(date -u +%Y%m%dT%H%M%SZ)
state_home=${XDG_STATE_HOME:-$HOME/.local/state}
result=$state_home/wonkoos/bob-vm-tests/$backup_id-$run_id
[[ ! -e $result ]] || { echo "result path already exists: $result" >&2; exit 1; }
work=$(mktemp -d /tmp/bob-vm-test.XXXXXX)
vm_pid=
trap 'if [[ -n ${vm_pid:-} ]]; then kill "$vm_pid" 2>/dev/null || true; wait "$vm_pid" 2>/dev/null || true; fi; chmod -R u+w "$work" 2>/dev/null || true; rm -rf "$work"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
runtime=$work/runtime
shared=$work/shared
install -d -m 0700 "$result" "$runtime" "$shared"

echo "staging the backup for the isolated VM"
sudo "$BOB_TAR" --acls --xattrs --numeric-owner -C "$backup" -cf - . \
  | zstd -T0 -3 -q -o "$shared/backup.tar.zst"
(
  cd "$shared"
  sha256sum backup.tar.zst > backup.tar.zst.sha256
)
chmod 0400 "$shared"/*
chmod 0500 "$shared"

timeout_seconds=3600
startup_timeout_seconds=120
if [[ ! -r /dev/kvm || ! -w /dev/kvm ]]; then
  timeout_seconds=7200
  startup_timeout_seconds=600
  echo "warning: /dev/kvm is unavailable; QEMU will use slower TCG emulation" >&2
fi

run_vm() {
  local attempt=$1 child_pid elapsed pids status

  printf '\n--- VM attempt %s ---\n' "$attempt" >> "$result/serial.log"
  timeout --signal=TERM --kill-after=30s "$timeout_seconds" \
    env \
      NIX_DISK_IMAGE="$work/bob.qcow2" \
      SHARED_DIR="$shared" \
      TMPDIR="$runtime" \
      USE_TMPDIR=1 \
      "$BOB_VM_RUNNER" >> "$result/serial.log" 2>&1 &
  vm_pid=$!

  for ((elapsed = 0; elapsed < startup_timeout_seconds; elapsed += 2)); do
    if grep -Eq 'Linux version|Welcome to' "$result/serial.log"; then
      wait "$vm_pid"
      status=$?
      vm_pid=
      return "$status"
    fi
    if ! kill -0 "$vm_pid" 2>/dev/null; then
      wait "$vm_pid"
      status=$?
      vm_pid=
      return "$status"
    fi
    sleep 2
  done

  child_pid=$(pgrep -P "$vm_pid" | head -n 1 || true)
  pids=$vm_pid
  [[ -z $child_pid ]] || pids+=,$child_pid
  {
    date -Ins
    free -h
    ps -o pid,ppid,stat,wchan:32,etimes,rss,vsz,cmd -p "$pids"
    if [[ -n $child_pid ]]; then
      printf '\n[cmdline]\n'
      tr '\0' ' ' < "/proc/$child_pid/cmdline"
      printf '\n\n[status]\n'
      sed -n '1,80p' "/proc/$child_pid/status"
      printf '\n[wchan]\n'
      cat "/proc/$child_pid/wchan"
      printf '\n\n[stack]\n'
      cat "/proc/$child_pid/stack" 2>&1 || true
      printf '\n[fds]\n'
      ls -l "/proc/$child_pid/fd"
    fi
  } > "$result/startup-attempt-$attempt.txt" 2>&1

  [[ -z $child_pid ]] || kill "$child_pid" 2>/dev/null || true
  kill "$vm_pid" 2>/dev/null || true
  wait "$vm_pid" 2>/dev/null || true
  vm_pid=
  return 125
}

echo "starting disposable Bob VM; results will be saved in $result"
set +e
vm_status=125
for attempt in 1 2; do
  if (( attempt > 1 )); then
    chmod -R u+w "$runtime" 2>/dev/null || true
    rm -rf "$runtime" "$work/bob.qcow2"
    install -d -m 0700 "$runtime"
  fi
  run_vm "$attempt"
  vm_status=$?
  (( vm_status == 125 )) || break
done
set -e

if [[ -d $runtime/xchg ]]; then
  cp -a "$runtime/xchg/." "$result/"
fi

if (( vm_status == 0 )) && [[ -e $result/PASS && ! -e $result/FAIL ]]; then
  echo "Bob restore test passed: $result"
  exit 0
fi

if (( vm_status == 125 )); then
  echo "Bob VM produced no kernel output after two attempts; inspect $result/startup-attempt-*.txt" >&2
elif (( vm_status == 124 )); then
  echo "Bob restore test timed out after $timeout_seconds seconds: $result" >&2
else
  echo "Bob restore test failed (VM exit $vm_status): $result" >&2
fi
exit 1
