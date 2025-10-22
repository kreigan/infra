# Infrastructure Automation

This repository contains infrastructure automation tools and configurations for managing homelab infrastructure.

## Structure

- **[ansible/](ansible/)** - Ansible playbooks, roles, and inventory for infrastructure provisioning
- **.taskfiles/** - Task automation using [Taskfile](https://taskfile.dev/)

## Quick Start

### Prerequisites

- Ansible >= 2.9
- Python >= 3.8
- [Task](https://taskfile.dev/) (for automation tasks)
- [1Password CLI](https://developer.1password.com/docs/cli/) (for secret management)

### Configuration

1. Configure host-specific variables in `ansible/files/host_config/<hostname>.yml`
2. Generate inventory variables: `task ansible:generate-config`
3. Run playbooks as needed (see [ansible/README.md](ansible/README.md))

## Available Playbooks

- **Storage Backup** - Automated BTRFS snapshot backup to S3-compatible storage using restic
  - See [ansible/playbooks/storage/backup/](ansible/playbooks/storage/backup/)

## Automation Tasks

View available tasks:
```bash
task --list
```

## Secret Management

This repository uses 1Password for secret management. Sensitive values are stored as references in the format:

```yaml
password: op://vault/item/field
```

The `task ansible:generate-config` command resolves these references using the 1Password CLI before generating the actual inventory files.

See [Secret Reference Syntax](https://developer.1password.com/docs/cli/secret-reference-syntax/) for more details.
