# Ansible Configuration

This directory contains Ansible playbooks, inventory, and configuration files for infrastructure automation.

## Directory Structure

```
ansible/
├── files/
│   └── host_config/          # Host-specific configuration sources
│       └── <hostname>.yml    # Configuration per host
├── inventory/
│   └── host_vars/            # Generated host variables
│       └── <hostname>/
│           └── 99-config.secret.yml  # Auto-generated from host_config
├── playbooks/
└── requirements.yaml         # Ansible Galaxy requirements
```

## Inventory Structure

### Host Configuration Files

Each managed host has a configuration file in `files/host_config/<hostname>.yml`. These files:
- Contain host-specific variables
- Can reference 1Password secrets using `op://` syntax
- Are processed by the `task ansible:generate-config` command

### Generated Host Variables

The `task ansible:generate-config` command:
1. Reads files from `files/host_config/*.yml`
2. Resolves 1Password secret references using the `op` CLI
3. Generates `inventory/host_vars/<hostname>/99-config.secret.yml`

These generated files are:
- Ignored by git (`.gitignore`)
- Contain plaintext secrets (never commit!)
- Should be regenerated whenever host_config files change

## Playbooks

### Storage Backup

Located in [playbooks/storage/backup/](playbooks/storage/backup/)

Automates BTRFS snapshot backups to S3-compatible storage using Snapper, Restic, and Resticprofile.

See the [playbook README](playbooks/storage/backup/README.md) for detailed configuration and usage.

## Task Automation

### generate-config

Generates host variable files from `host_config` sources with 1Password secret resolution.

**Generate for all hosts:**
```bash
task ansible:generate-config
```

**Generate for specific host:**
```bash
task ansible:generate-config HOSTNAME=storage
```

**How it works:**
1. Finds `*.yml` files in `files/host_config/`
2. For each file, creates `inventory/host_vars/<hostname>/`
3. Runs `op inject` to resolve secret references
4. Writes output to `99-config.secret.yml` omitting comment lines

## Requirements

Install Ansible Galaxy collections and roles:
```bash
ansible-galaxy install -r requirements.yaml
```

## Best Practices

1. **Never commit secrets** - Use 1Password references in `host_config` files
2. **Regenerate after changes** - Run `task ansible:generate-config` after modifying `host_config` files
3. **Use tags** - Run specific parts of playbooks with `--tags`
4. **Fail fast** - Include validation tasks in playbooks to catch misconfigurations early
