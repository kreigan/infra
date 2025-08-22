# Infrastructure Automation

This repository contains infrastructure automation tools and configurations for managing cloud and on-premises infrastructure.

## BTRFS Backup Solution

This branch provides automated BTRFS snapshot backup to Backblaze B2 using Restic.

### Features
- Automated BTRFS snapshot creation
- Incremental backups to Backblaze B2
- Restic-based encryption and deduplication  
- Comprehensive validation and testing scripts
- 1Password integration for secure credential management

### Quick Start
1. Copy environment template: `cp .env.example .env`
2. Configure 1Password references in `.env`
3. Deploy: `ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/btrfs-backup.yml`
4. Validate: `./scripts/validate-backup-deployment.sh`
5. Test: `./scripts/test-backup-functionality.sh`

### Testing
- `scripts/validate-backup-deployment.sh` - Validate deployment prerequisites
- `scripts/test-backup-functionality.sh` - Test actual backup/restore operations  
- `scripts/smoke-test.sh` - Quick health checks
