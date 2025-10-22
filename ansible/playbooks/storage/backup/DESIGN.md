# Backup System Design Documentation

## Overview

This document describes the complete design and architecture of the automated BTRFS snapshot backup system deployed by this playbook. The solution integrates three key technologies:

- **Snapper**: Creates and manages BTRFS snapshots
- **Restic**: Provides deduplicating, encrypted backups to S3-compatible storage
- **Resticprofile**: Orchestrates backup operations with scheduling via systemd

## Architecture

### System Components

```
┌─────────────────────────────────────────────────────────────┐
│                    Host System (storage)                    │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌──────────────┐                                           │
│  │   Snapper    │  Creates BTRFS snapshots                  │
│  │   Timeline   │  (automatic, scheduled)                   │
│  └──────┬───────┘                                           │
│         │                                                   │
│         │ triggers                                          │
│         ▼                                                   │
│  ┌──────────────────────┐                                   │
│  │  Snapper Plugin      │  Detects new snapshots            │
│  │  (00-plugin.sh)      │  Updates snapshot state           │
│  └──────┬───────────────┘                                   │
│         │                                                   │
│         │ writes                                            │
│         ▼                                                   │
│  ┌──────────────────────┐                                   │
│  │  Snapshot State      │  DEVICE, SUBVOLID env vars        │
│  │  (/etc/resticprofile │                                   │
│  │   /envs/<profile>)   │                                   │
│  └──────┬───────────────┘                                   │
│         │                                                   │
│         │ read by (scheduled)                               │
│         ▼                                                   │
│  ┌──────────────────────┐                                   │
│  │  Resticprofile       │  Orchestrates backup workflow     │
│  │  (systemd timer)     │                                   │
│  └──────┬───────────────┘                                   │
│         │                                                   │
│         │ calls                                             │
│         ▼                                                   │
│  ┌──────────────────────┐                                   │
│  │  Backup Assistant    │  Mounts/unmounts snapshots        │
│  │  (backup-assist.sh)  │                                   │
│  └──────┬───────────────┘                                   │
│         │                                                   │
│         │ provides                                          │
│         ▼                                                   │
│  ┌──────────────────────┐                                   │
│  │  Restic              │  Performs incremental backup      │
│  │                      │  to S3 storage                    │
│  └──────┬───────────────┘                                   │
│         │                                                   │
│         │ stores to                                         │
│         ▼                                                   │
│  ┌──────────────────────┐                                   │
│  │  Backblaze B2        │  S3-compatible storage backend    │
│  │  (or other S3)       │                                   │
│  └──────────────────────┘                                   │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

## Component Details

### 1. Snapper Integration

**Purpose**: Creates and manages BTRFS filesystem snapshots on a timeline.

**Configuration Location**: `/etc/snapper/configs/<target-name>`

**Key Settings** (from [vars/main.yml](vars/main.yml:15-32)):
- Timeline snapshots: hourly/daily/monthly/yearly retention
- Automatic cleanup of old snapshots
- Space management (limits)
- Background comparison enabled

**Snapper Plugin** ([snapper-plugin.sh.j2](tasks/templates/scripts/snapper-plugin.sh.j2)):
- Installed at: `/usr/lib/snapper/plugins/00-plugin.sh`
- Triggered automatically when snapper creates a new snapshot
- Responsibilities:
  1. Detects new snapshot creation events
  2. Retrieves the BTRFS subvolume ID of the new snapshot
  3. Identifies which resticprofile profiles are configured for the subvolume
  4. Updates the snapshot state files with device and subvolume ID

**State Files**: `/etc/resticprofile/envs/<profile-name>/snapshot`
```bash
DEVICE=/dev/sdX
SUBVOLID=12345
```

### 2. Resticprofile Orchestration

**Purpose**: Provides a declarative configuration layer over restic with built-in systemd scheduling.

**Main Configuration**: `/etc/resticprofile/profiles.yaml` ([resticprofile.yaml.j2](tasks/templates/configs/resticprofile.yaml.j2))

**Key Features**:

#### Global Settings
- Automatic repository initialization
- Memory limits (min-memory: 100MB)
- Systemd as scheduler backend
- Bash shell for script execution
- Centralized logging to `/var/log/resticprofile.log`

#### Mixins Architecture

Mixins are reusable configuration blocks used to reduce duplication. The playbook defines:

- **`repo-creds`**: Loads systemd credential drop-in files. Requires `$REPO` variable to specify which repository's credentials to load.
- **`default-tag`**: Uses profile name as backup tag unless overridden.

```yaml
mixins:
  repo-creds:
    systemd-drop-in-files...:
      - "repositories/$REPO/99-systemd-creds.conf"

  default-tag:
    tag: "{{ .Profile.Name }}"
```

#### Profile Inheritance

The `default` profile defines common settings inherited by all backup profiles:

```yaml
profiles:
  default:
    env-file:
      - "envs/{{ .Profile.Name }}/mount"    # MOUNT_POINT variable
      - "envs/{{ .Profile.Name }}/snapshot"  # DEVICE, SUBVOLID variables

    backup:
      one-file-system: true
      group-by: tags
      verbose: true
      use:
        - default-tag

      # Lifecycle hooks
      run-before: /etc/resticprofile/backup-assist.sh mount
      run-finally: /etc/resticprofile/backup-assist.sh unmount
```

#### Profile Files

Each backup target gets its own profile file at `/etc/resticprofile/profile.d/<target-name>.yaml` ([resticprofile-profile.yaml.j2](tasks/templates/configs/resticprofile-profile.yaml.j2)):

```yaml
version: "2"

profiles:
  photos:
    inherit: default
    use:
      - name: repo-creds
        REPO: photos
    backup:
      source: /backup/photos
      schedule: "00/2:05"
      tag: [photos, media]
```

#### Scheduler Mechanism

Resticprofile generates systemd timer and service units:

1. Command `resticprofile schedule --all` creates/updates units
2. Generated unit names:
   - Service: `resticprofile-backup@profile-<profile-name>.service`
   - Timer: `resticprofile-backup@profile-<profile-name>.timer`
3. Timers use systemd `OnCalendar` syntax
4. Services run as `Type=oneshot`
5. Logs to `/var/log/resticprofile.log` and `/var/log/resticprofile-scheduled.log`

### 3. Systemd Credentials System

**Purpose**: Securely store and inject sensitive credentials (S3 keys, restic passwords) into backup processes.

**Why Systemd Credentials?**
- Credentials encrypted at rest
- Automatically decrypted only when service runs
- Credentials never touch disk in plaintext
- Scoped to specific systemd units
- Supports TPM-based encryption

**Implementation** ([create-repository-secret.yml](tasks/create-repository-secret.yml)):

1. **Encryption**: Uses `systemd-creds encrypt` via Ansible module
   ```yaml
   community.general.systemd_creds_encrypt:
     name: "photos-repository"
     secret: "s3:https://s3.us-west-002.backblazeb2.com/bucket-name/photos"
   ```

2. **Storage**: Encrypted credentials stored per repository
   ```
   /etc/resticprofile/repositories/<repo-name>/
   ├── repository           # Encrypted S3 URL
   ├── password            # Encrypted restic password
   └── aws-credentials     # Encrypted AWS credentials file
   ```

3. **Drop-in Configuration** ([restic-repo-systemd-dropin.j2](tasks/templates/systemd/restic-repo-systemd-dropin.j2)):
   ```ini
   [Service]
   PrivateMounts=yes

   LoadCredentialEncrypted=photos-repository:/etc/resticprofile/repositories/photos/repository
   Environment=RESTIC_REPOSITORY_FILE=%d/photos-repository

   LoadCredentialEncrypted=photos-password:/etc/resticprofile/repositories/photos/password
   Environment=RESTIC_PASSWORD_FILE=%d/photos-password

   LoadCredentialEncrypted=photos-aws-credentials:/etc/resticprofile/repositories/photos/aws-credentials
   Environment=AWS_SHARED_CREDENTIALS_FILE=%d/photos-aws-credentials

   Environment=AWS_REGION=us-west-002
   ```

**Credential Flow**:
1. Systemd timer triggers backup service
2. `LoadCredentialEncrypted` directives decrypt credentials to temporary directory (`%d`)
3. Environment variables point to decrypted files in `%d`
4. Restic reads credentials from environment variables
5. Service exits, temporary credentials are destroyed
6. `PrivateMounts=yes` isolates mount operations

### 4. Backup Assistant Script

**Location**: `/etc/resticprofile/backup-assist.sh` ([backup-assist.sh](tasks/files/backup-assist.sh))

**Purpose**: Safely mount and unmount BTRFS snapshots for backup operations.

**Mount Operation** (`run-before` hook):
1. Read environment variables: `MOUNT_POINT`, `DEVICE`, `SUBVOLID`
2. Validate all required variables are set
3. Validate device exists
4. Check if already mounted
5. Mount snapshot read-only: `mount -o ro,subvolid=$SUBVOLID $DEVICE $MOUNT_POINT`
6. Log all operations to systemd journal with correlation ID

**Unmount Operation** (`run-finally` hook):
1. Read `MOUNT_POINT` environment variable
2. Check if mounted
3. Unmount: `umount $MOUNT_POINT`
4. Log operation

**Error Handling**:
- Exit codes 10-12: Non-critical errors (skip backup)
  - 10: No DEVICE set (first run)
  - 11: No SUBVOLID set (first run)
  - 12: Already mounted (unexpected but recoverable)
- Exit code 1: Critical errors (fail backup)

**Correlation ID**: Each invocation generates unique ID for log tracing:
```
[backup-assist-1234567890-12345-6789] Command: mount, mount point: /backup/photos
```

### 5. Restic Backup Engine

**Purpose**: Performs incremental, deduplicated, encrypted backups to S3.

**Integration**:
- Called by resticprofile as subprocess
- Reads credentials from systemd-injected environment variables
- Backs up from snapshot mount point
- Tags snapshots with profile name

**Features Used**:
- One file system (`--one-file-system`)
- Group snapshots by tags
- Automatic repository initialization
- Incremental backups with deduplication
- Client-side encryption

## Deployment Workflow

### Initial Setup (Ansible)

1. **Validation** ([validate-configuration.yml](tasks/validate-configuration.yml))
   - Verify repository credentials present
   - Validate target configurations
   - Check repository references exist
   - Validate systemd calendar schedules
   - Ensure no mount point conflicts

2. **Package Deployment** ([deploy.yml](tasks/deploy.yml))
   - Install system packages (btrfs-progs, wget, acl, yq)
   - Create `restic` system user
   - Deploy restic binary
   - Deploy resticprofile binary
   - Deploy snapper package

3. **Configuration**
   - Create directory structure
   - Deploy configuration files
   - Set ownership and permissions

4. **Snapper Configuration** ([configure-snapshot.yml](tasks/configure-snapshot.yml))
   - Create snapper configuration per target
   - Set retention policies
   - Configure allowed users and ACL sync

5. **Repository Setup** ([make-repository.yml](tasks/make-repository.yml))
   - Encrypt and store repository credentials
   - Create systemd drop-in configuration

6. **Scheduling**
   - Handler triggers: `resticprofile schedule --all`
   - Generates and enables systemd timers

### Runtime Operation

#### Phase 1: Snapshot Creation
1. Snapper timeline creates BTRFS snapshot
2. Snapper calls plugin: `/usr/lib/snapper/plugins/00-plugin.sh create-snapshot ...`
3. Plugin determines snapshot's BTRFS subvolume ID
4. Plugin updates state file with DEVICE and SUBVOLID

#### Phase 2: Scheduled Backup
1. Timer triggers: `resticprofile-backup@profile-<name>.timer`
2. Systemd starts service: `resticprofile-backup@profile-<name>.service`
3. Service loads encrypted credentials
4. Service reads environment files

#### Phase 3: Pre-Backup Hook
1. Resticprofile calls: `backup-assist.sh mount`
2. Script validates environment variables
3. Script mounts snapshot read-only
4. Mount point contains snapshot view

#### Phase 4: Backup Execution
1. Restic reads credentials from environment
2. Restic connects to S3 repository
3. Restic initializes repository (if first run)
4. Restic performs incremental backup
5. Restic applies tags
6. Restic uploads changed blocks

#### Phase 5: Cleanup Hook
1. Resticprofile calls: `backup-assist.sh unmount`
2. Script unmounts snapshot
3. Private mount namespace destroyed

#### Phase 6: Logging
- Backup logs to `/var/log/resticprofile-scheduled.log` and systemd journal
- Assistant script logs to systemd journal (identifier: `backup-assist`)
- Snapper plugin logs to systemd journal (identifier: `snapper-plugin`)

## Security Architecture

### Credential Isolation
- Repository passwords encrypted with systemd-creds
- S3 credentials encrypted with systemd-creds
- Credentials decrypted only in memory during service execution
- Credentials scoped to specific systemd units
- No plaintext credentials on disk

### Filesystem Isolation
- Snapshots mounted read-only
- `PrivateMounts=yes` isolates mount operations
- Dedicated `restic` system user with minimal privileges
- No login shell for restic user

### Network Security
- S3 communication over HTTPS
- Restic client-side encryption
- AWS credentials limited to specific bucket

## Configuration Variables

### Repository Configuration
```yaml
repositories:
  <repo-name>:
    password: <restic-repository-password>
    path: <repository-path-on-s3>
    bucket:
      name: <s3-bucket-name>
      endpoint: <s3-endpoint-url>
      region: <s3-region>
      credentials:
        key_id: <aws-access-key-id>
        secret: <aws-secret-access-key>
```

### Target Configuration
```yaml
targets:
  <target-name>:
    snapshot:
      path: <absolute-path-to-btrfs-subvolume>
      vars: <optional-snapper-configuration-overrides>
    backup:
      repository: <repository-name-reference>
      mount: <mount-point-for-snapshot>
      schedule: <systemd-calendar-expression>
      tags: <optional-list-of-backup-tags>
```

### Optional Overrides
- Restic/resticprofile versions
- Binary paths
- Directory locations
- Log rotation policies
- Snapper retention policies

## Error Handling

### Backup Assistant Exit Codes
- `0`: Success
- `1`: Critical error (mount/unmount failed)
- `10`: DEVICE not set (first run, skips backup)
- `11`: SUBVOLID not set (first run, skips backup)
- `12`: Already mounted (unexpected but continues)

## File Structure

```
backup/
├── backup.yml                           # Main playbook
├── tasks/
│   ├── deploy.yml                       # Package installation
│   ├── deploy-restic.yml               # Restic deployment
│   ├── deploy-resticprofile.yml        # Resticprofile deployment
│   ├── deploy-snapper.yml              # Snapper deployment
│   ├── configure-profiles.yml          # Profile configuration
│   ├── configure-snapshot.yml          # Snapshot configuration
│   ├── make-repository.yml             # Repository setup
│   ├── create-repository-secret.yml    # Credential management
│   ├── validate-configuration.yml      # Configuration validation
│   ├── files/
│   │   └── backup-assist.sh            # Mount/unmount helper
│   └── templates/
│       ├── configs/
│       │   ├── resticprofile.yaml.j2          # Main config
│       │   └── resticprofile-profile.yaml.j2  # Profile template
│       ├── scripts/
│       │   └── snapper-plugin.sh.j2           # Snapper integration
│       └── systemd/
│           └── restic-repo-systemd-dropin.j2  # Credential injection
└── vars/
    └── main.yml                         # Default variables
```
