#!/bin/bash
set -e

CORRELATION_ID="backup-assist-$(date +%s)-$$-$RANDOM"

function log() {
    local level="$1"
    shift
    case "$level" in
        debug|info|notice|warning|err|crit|alert|emerg) ;;
        *) level="info" ;;
    esac
    echo "[$CORRELATION_ID] $*" | systemd-cat -t backup-assist -p "$level"
}

function log-debug() { log debug "$@"; }
function log-info() { log info "$@"; }
function log-warning() { log warning "$@"; }
function log-err() { log err "$@"; }

if [ $# -eq 0 ]; then
    log-err "No command provided. Usage: $0 <mount|unmount>"
    exit 1
fi

COMMAND="$1"

if [ "$COMMAND" != "mount" ] && [ "$COMMAND" != "unmount" ]; then
    log-err "Invalid command: '$COMMAND'. Usage: $0 <mount|unmount>"
    exit 1
fi

if [ -z "$MOUNT_POINT" ]; then
    log-err "MOUNT_POINT environment variable is not set"
    exit 1
fi

if [ ! -d "$MOUNT_POINT" ]; then
    log-err "Mount point directory does not exist: $MOUNT_POINT"
    exit 1
fi

log-info "Command: $COMMAND, mount point: $MOUNT_POINT"

if [ "$COMMAND" == "mount" ]; then
    # Validate snapshot environment variables
    if [ -z "$DEVICE" ]; then
        log-warning "DEVICE environment variable not set (first run or no snapshot available)"
        log-info "Skipping mount operation"
        exit 10
    fi

    if [ -z "$SUBVOLID" ]; then
        log-warning "SUBVOLID environment variable not set (first run or no snapshot available)"
        log-info "Skipping mount operation"
        exit 11
    fi

    # Validate device exists
    if [ ! -b "$DEVICE" ] && [ ! -e "$DEVICE" ]; then
        log-err "Device does not exist: $DEVICE"
        exit 1
    fi

    # Check if already mounted
    if mountpoint -q "$MOUNT_POINT" 2>/dev/null; then
        log-warning "Already mounted: $MOUNT_POINT (unexpected with PrivateMounts)"
        exit 12
    fi

    # Mount the snapshot
    log-info "Mounting $DEVICE (subvolid=$SUBVOLID) to $MOUNT_POINT"

    mountError=$(mount -o ro,subvolid=$SUBVOLID "$DEVICE" "$MOUNT_POINT" 2>&1)
    mountResult=$?

    if [ $mountResult -ne 0 ]; then
        log-err "Failed to mount $DEVICE (subvolid=$SUBVOLID) to $MOUNT_POINT: $mountError"
        exit 1
    fi

    log-info "Successfully mounted $DEVICE (subvolid=$SUBVOLID) to $MOUNT_POINT"

elif [ "$COMMAND" == "unmount" ]; then
    # Check if mounted
    if ! mountpoint -q "$MOUNT_POINT" 2>/dev/null; then
        log-debug "Not mounted: $MOUNT_POINT (nothing to unmount)"
        exit 0
    fi

    # Unmount
    log-info "Unmounting $MOUNT_POINT"

    umountError=$(umount "$MOUNT_POINT" 2>&1)
    umountResult=$?

    if [ $umountResult -ne 0 ]; then
        log-err "Failed to unmount $MOUNT_POINT: $umountError"
        exit 1
    fi

    log-info "Successfully unmounted $MOUNT_POINT"
fi

exit 0
