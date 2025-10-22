# BTRFS Snapshot Backup Playbook

Automates BTRFS snapshot backups to S3-compatible storage using Snapper, Restic, and Resticprofile.

## Overview

This playbook sets up an automated backup system that:
1. Creates BTRFS snapshots on a timeline (using Snapper)
2. Backs up snapshots to S3 storage (using Restic)
3. Schedules and orchestrates backups (using Resticprofile with systemd timers)

**Key Features**:
- Automated snapshot creation with configurable retention
- Incremental, encrypted, deduplicated backups
- Secure credential management via systemd-creds
- Scheduled backups with systemd timers
- Read-only snapshot mounts for consistency

## Architecture

The system integrates three main components:

```
Snapper (Timeline) → Snapper Plugin → Resticprofile (Scheduled) → Backup Assistant → Restic → S3 Storage
    ↓                     ↓                   ↓                        ↓
BTRFS Snapshots    State Files    Systemd Timers           Mount Snapshots
```

**Workflow**:
1. Snapper creates BTRFS snapshots automatically
2. Snapper plugin detects new snapshots and updates state files with device/subvolume ID
3. Systemd timer triggers resticprofile on schedule
4. Backup assistant mounts the snapshot read-only
5. Restic performs incremental backup to S3
6. Backup assistant unmounts the snapshot

For detailed architecture, see [docs/backup/design.md](../../../../docs/backup/design.md).

## Quick Start

### Prerequisites

- BTRFS filesystem for directories to back up
- S3-compatible storage account (tested with Backblaze B2)
- Ansible >= 2.9
- 1Password CLI (for secret management, optional)

### Configuration

1. **Configure backup targets** in `ansible/files/host_config/<hostname>.yml`:

```yaml
restic:
  version: "0.18.0"

resticprofile:
  version: "0.31.0"

repositories:
  mydata:
    password: "your-restic-password"  # or op://vault/item/field
    path: "mydata"
    bucket:
      name: "my-backup-bucket"
      endpoint: "s3.us-west-002.backblazeb2.com"
      region: "us-west-002"
      credentials:
        key_id: "your-access-key-id"
        secret: "your-secret-key"

targets:
  mydata:
    snapshot:
      path: /srv/data  # Must be on BTRFS
    backup:
      repository: mydata
      mount: /backup/mydata
      schedule: "00/2:05"  # Every 2 hours at :05
```

2. **Generate host variables** (if using 1Password secrets):

```bash
task ansible:generate-config HOSTNAME=<hostname>
```

3. **Deploy**:

```bash
cd ansible
ansible-playbook -i inventory/hosts.yml playbooks/storage/backup.yml
```

4. **Verify**:

```bash
# Check scheduled backups
systemctl list-timers 'resticprofile-*'

# Check snapper snapshots
snapper -c mydata list
```

## Playbook Tags

Allow to run specific parts of the playbook:

- `validate` - Validate configuration only
- `deploy` - Install packages and binaries
- `upgrade` - Upgrade to configured versions
- `configure` - Configure all components
- `profiles` - Configure resticprofile profiles
- `snapshots` - Configure snapper snapshots
- `scripts` - Deploy helper scripts

**Examples**:

```bash
# Update configuration only
ansible-playbook -i inventory/hosts.yml playbooks/storage/backup.yml --tags configure

# Upgrade restic/resticprofile versions
ansible-playbook -i inventory/hosts.yml playbooks/storage/backup.yml --tags upgrade

# Reconfigure profiles after changing schedules
ansible-playbook -i inventory/hosts.yml playbooks/storage/backup.yml --tags profiles
```

## Configuration Reference

### Repository Settings

```yaml
repositories:
  <name>:
    password: <restic-password>     # Encrypts backups
    path: <path-in-bucket>          # Subdirectory in S3 bucket
    bucket:
      name: <bucket-name>
      endpoint: <s3-endpoint>
      region: <s3-region>
      credentials:
        key_id: <access-key-id>
        secret: <secret-access-key>
```

**Best Practice**: Use 1Password references for credentials:
```yaml
password: op://automation/Restic/mydata/password
```

### Target Settings

```yaml
targets:
  <name>:
    snapshot:
      path: <directory>              # Directory to backup (must be BTRFS)
      vars: {}                       # Optional: snapper config overrides
    backup:
      repository: <repo-name>        # References repository above
      mount: <mount-point>           # Temporary mount point for snapshots
      schedule: <systemd-timer>      # Backup schedule
      tags: []                       # Optional: custom backup tags
```

### Schedule Syntax

Uses systemd timer format:

- `*:00` - Every hour
- `00/2:05` - Every 2 hours at :05
- `daily` - Daily at midnight
- `Mon *-*-* 00:00:00` - Mondays at midnight

### Snapshot Retention

Default policy (override via `targets.<name>.snapshot.vars`):

- **Hourly**: 10 snapshots
- **Daily**: 10 snapshots
- **Monthly**: 10 snapshots
- **Yearly**: 10 snapshots
- **Total limit**: 50 snapshots
- **Min age before cleanup**: 30 minutes

**Override example**:
```yaml
targets:
  mydata:
    snapshot:
      vars:
        TIMELINE_LIMIT_HOURLY: 24
        TIMELINE_LIMIT_DAILY: 30
        NUMBER_LIMIT: 100
```

## Daily Operations

### Check Backup Status

```bash
# View scheduled backups
systemctl list-timers 'resticprofile-*'

# Check timer for `mydata` profile
systemctl status resticprofile-backup@profile-mydata.timer

# View recent backup logs for `mydata` profile
journalctl -u resticprofile-backup@profile-mydata.service -n 50

# View backup assistant logs
journalctl -t backup-assist -n 50

# View snapper plugin logs
journalctl -t snapper-plugin -n 50
```

### Manual Backup

Use [backup_test](../backup_test.yml) playbook to trigger a backup manually for a specific profile.

The playbook:

- changes the resticprofile backup schedule to run in 5 seconds
- waits for the backup to complete by polling the service status
- restores the original schedule once done (failed or succeeded)

```bash
ansible-playbook -i inventory/hosts.yml playbooks/storage/backup_test.yml -e profile=photos
```

## Maintenance

### Logs

Log files:
- `/var/log/resticprofile.log` - Manual operations
- `journalctl -u resticprofile-backup@profile-{PROFILE}.service` - All resticprofile logs
- `journalctl -t backup-assist` - Mount/unmount operations
- `journalctl -t snapper-plugin` - Post-snapshot processing

Log file rotation is configured automatically (default setting is weekly, keep 4 weeks).

## Troubleshooting

### Backup Not Running

```bash
# Check timer status
systemctl list-timers 'resticprofile-*'

# If missing, regenerate
resticprofile schedule --all

# Check logs
journalctl -u resticprofile-backup@profile-mydata.service -n 100
```

### Mount Issues

```bash
# Check backup assistant logs for mount/unmount errors
journalctl -t backup-assist -n 100
```

### Last Snapshot Volume ID Not Updated

```bash
# Check snapper plugin logs
journalctl -t snapper-plugin -n 100
```

## Security

- **Credentials**: Encrypted at rest using systemd-creds
- **Snapshots**: Mounted read-only
- **Backups**: Client-side encryption with Restic
- **Transport**: HTTPS to S3

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

## Documentation

- [DESIGN.md](DESIGN.md) - Complete architecture and implementation details
