#!/bin/bash
# Local test script that mirrors the CI workflow in .github/workflows/ci.yml.
# Runs the container build and the "bootc install to-disk" test.
#
# Usage:
#   sudo ./test-local.sh          # build + test
#   sudo ./test-local.sh build    # build only
#   sudo ./test-local.sh test     # test only (image must already exist)
set -euo pipefail

IMAGE=localhost/bootupd:latest
DISK=myimage.raw
DISK_SIZE=10G

cleanup() {
    echo ":: Cleaning up"
    if mountpoint -q /mnt 2>/dev/null; then
        umount /mnt || true
    fi
    if [ -n "${LOOPDEV:-}" ]; then
        losetup -d "$LOOPDEV" 2>/dev/null || true
    fi
    rm -f "$DISK"
}

do_build() {
    echo ":: Building container image"
    podman build -t "$IMAGE" -f Dockerfile .
}

do_test() {
    echo ":: Creating ${DISK_SIZE} disk image"
    truncate -s "$DISK_SIZE" "$DISK"
    trap cleanup EXIT

    echo ":: Running bootc install to-disk"
    podman run --rm --privileged \
        -v .:/target --pid=host --security-opt label=disable \
        -v /var/lib/containers:/var/lib/containers \
        -v /dev:/dev \
        "$IMAGE" bootc install to-disk --skip-fetch-check \
        --disable-selinux --generic-image --via-loopback /target/"$DISK"

    echo ":: Verifying disk contents"
    losetup -P -f "$DISK"
    LOOPDEV=$(losetup -a "$DISK" --output NAME -n)

    # Check ESP partition
    esp_part=$(sfdisk -l -J "$LOOPDEV" | jq -r \
        '.partitiontable.partitions[] | select(.type == "C12A7328-F81F-11D2-BA4B-00A0C93EC93B").node')
    if [ -z "$esp_part" ]; then
        echo "FAIL: no ESP partition found on $LOOPDEV"
        exit 1
    fi

    mount "$esp_part" /mnt/

    arch=$(uname -m)
    if [ "$arch" = "x86_64" ]; then
        shim="shimx64.efi"
    else
        shim="shimaa64.efi"
    fi

    echo ":: Checking for grub.cfg and $shim on ESP"
    ls /mnt/EFI/centos/grub.cfg /mnt/EFI/centos/"$shim"
    umount /mnt

    # Check root partition
    root_part=$(sfdisk -l -J "$LOOPDEV" | jq -r \
        '.partitiontable.partitions[] | select(.name == "root").node')
    mount "$root_part" /mnt/

    echo ":: Checking /boot/grub2/grub.cfg permissions"
    for f in /mnt/boot/grub2/grub.cfg /mnt/boot/grub2/bootuuid.cfg /mnt/boot/grub2/grubenv; do
        perm=$(stat -c '%a' "$f") || exit 1
        if [ "$perm" != "600" ]; then
            echo "FAIL: $f has permissions $perm (expected 600)"
            exit 1
        fi
    done
    umount /mnt

    losetup -d "$LOOPDEV"
    unset LOOPDEV
    rm -f "$DISK"
    trap - EXIT

    echo ":: All tests passed"
}

cmd="${1:-all}"
case "$cmd" in
    build) do_build ;;
    test)  do_test ;;
    all)   do_build; do_test ;;
    *)     echo "Usage: $0 [build|test|all]"; exit 1 ;;
esac
