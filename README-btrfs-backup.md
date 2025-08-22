# BTRFS Backup to Backblaze B2 with Restic

This Ansible playbook configures automated BTRFS snapshot backups to Backblaze B2 using Restic.

## Features

- **BTRFS Snapshots**: Creates read-only snapshots before backup
- **Incremental Backups**: Restic deduplication for efficient storage
- **Configurable Retention**: Local snapshots and remote backup retention
- **Automated Scheduling**: Cron-based backup execution
- **Log Management**: Automated log rotation
- **Secure Configuration**: Ansible Vault for sensitive data

## Files Structure

```
ansible/
├── playbooks/
│   └── btrfs-backup.yml          # Main playbook
├── templates/
│   ├── backup-script.sh.j2       # Backup script template
│   └── restic-env.j2             # Restic environment variables
└── vars/
    ├── btrfs-backup.yml          # Configuration variables
    └── vault.yml.example         # Vault variables example
```

## Configuration

### 1. Configure 1Password Credentials

Create a 1Password item with the following fields:
- **Item Name**: `Backblaze B2 Backup`
- **Vault**: `Infrastructure` (or adjust `1password.env`)
- **Fields**:
  - `restic_password`: Repository encryption password
  - `bucket_name`: Backblaze B2 bucket name  
  - `region`: B2 region (e.g., `us-west-002`)
  - `access_key_id`: B2 application key ID
  - `secret_access_key`: B2 application key

Edit `ansible/1password.env` if using different item/vault names.

### 2. Configure Variables

Edit `ansible/vars/btrfs-backup.yml`:

- **Paths**: Adjust BTRFS mount point and subvolume paths
- **Retention**: Configure snapshot and backup retention policies
- **Schedule**: Set cron schedule for automated backups
- **Restic Version**: Specify Restic version to install

### 3. Inventory Setup

Ensure your inventory has a `storage` group with the target host.

## Usage

### Deploy Configuration

```bash
# Using 1Password CLI
op run --env-file=ansible/1password.env -- ansible-playbook -i inventory/hosts.yml playbooks/btrfs-backup.yml

# Alternative: export environment variables manually
export RESTIC_PASSWORD="your-password"
export S3_BUCKET_NAME="your-bucket"
export S3_REGION="us-west-002"
export AWS_ACCESS_KEY_ID="your-access-key-id"
export AWS_SECRET_ACCESS_KEY="your-secret-access-key"
export AWS_DEFAULT_REGION="us-west-002"
ansible-playbook -i inventory/hosts.yml playbooks/btrfs-backup.yml
```

### Manual Backup

```bash
# On target host
sudo -u restic /usr/local/bin/btrfs-backup.sh
```

### Check Backup Status

```bash
# View logs
sudo tail -f /var/log/btrfs-backup.log

# List Restic snapshots
sudo -u restic restic -r s3:https://s3.us-west-002.backblazeb2.com/your-bucket/storage-photos snapshots
```

## Configuration Options

### Backup Schedule Examples

```yaml
# Daily at 2 AM
backup_cron_minute: "0"
backup_cron_hour: "2"
backup_cron_day: "*"
backup_cron_month: "*"
backup_cron_weekday: "*"

# Weekly on Sunday at 3 AM
backup_cron_minute: "0"
backup_cron_hour: "3"
backup_cron_day: "*"
backup_cron_month: "*"
backup_cron_weekday: "0"
```

### Retention Policies

```yaml
# Local snapshots
snapshot_retention_count: 3

# Remote backups
backup_retention_daily: 7
backup_retention_weekly: 4
backup_retention_monthly: 6
backup_retention_yearly: 2
```

## Security Notes

- **Restricted User**: All operations run as `restic` user (no login shell)
- **Read-Only Access**: Photos subvolume has read-only ACLs for `restic` user
- **Limited Privileges**: Only BTRFS snapshot operations via sudo (no password)
- **Secure Storage**: Credentials managed via 1Password CLI
- **Encrypted Repository**: Restic repository encrypted with your password
- **Protected Config**: Environment variables stored in `/etc/restic/env` (restic user only)
- **1Password Session**: Required on deployment host

## Troubleshooting

### Check Restic Repository

```bash
sudo -u restic restic -r s3:https://s3.us-west-002.backblazeb2.com/your-bucket/storage-photos check
```

### Manual Snapshot Creation

```bash
sudo -u restic sudo btrfs subvolume snapshot -r /srv/.../storage/media/Photos /srv/.../snapshots/photos-test
```

### View Backup History

```bash
sudo -u restic restic -r s3:https://s3.us-west-002.backblazeb2.com/your-bucket/storage-photos snapshots --tag btrfs-photos
```

### Verify ACL Permissions

```bash
# Check Photos directory ACLs
getfacl /srv/.../storage/media/Photos

# Should show: user:restic:r-x
```