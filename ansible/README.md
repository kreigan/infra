# Ansible Configuration

This directory contains Ansible playbooks, inventory, and configuration files for infrastructure automation.

## Directory Structure

```
ansible/
├── files/
│   ├── group_config/         # Group-specific configuration sources
│   │   └── <groupname>.yml   # Configuration per group
│   └── host_config/          # Host-specific configuration sources
│       └── <hostname>.yml    # Configuration per host
├── inventory/
│   ├── group_vars/           # Generated group variables
│   │   └── <groupname>/
│   │       └── 99-config.secret.yml  # Auto-generated from group_config
│   └── host_vars/            # Generated host variables
│       └── <hostname>/
│           └── 99-config.secret.yml  # Auto-generated from host_config
├── playbooks/
└── requirements.yaml         # Ansible Galaxy requirements
```

## Inventory Structure

### Configuration Files

Configuration can be defined at two levels:

**Group Configuration** (`files/group_config/<groupname>.yml`):
- Contain group-wide variables
- Applied to all hosts in the group
- Can reference 1Password secrets using `op://` syntax
- Processed to `inventory/group_vars/<groupname>/99-config.secret.yml`

**Host Configuration** (`files/host_config/<hostname>.yml`):
- Contain host-specific variables
- Override group variables when defined
- Can reference 1Password secrets using `op://` syntax
- Processed to `inventory/host_vars/<hostname>/99-config.secret.yml`

### Generated Variables

The `task ansible:generate-config` command:
1. Reads files from `files/group_config/*.yml` and `files/host_config/*.yml`
2. Resolves 1Password secret references using the `op` CLI
3. Generates `inventory/group_vars/<groupname>/99-config.secret.yml` or `inventory/host_vars/<hostname>/99-config.secret.yml`

These generated files are:
- Ignored by git (`.gitignore`)
- Contain plaintext secrets (never commit!)
- Should be regenerated whenever config files change

## Playbooks

### Storage Backup

Located in [playbooks/storage/backup/](playbooks/storage/backup/)

Automates BTRFS snapshot backups to S3-compatible storage using Snapper, Restic, and Resticprofile.

See the [playbook README](playbooks/storage/backup/README.md) for detailed configuration and usage.

## Task Automation

### generate-config

Generates group and host variable files from configuration sources with 1Password secret resolution.

**Generate for all groups and hosts:**
```bash
task ansible:generate-config
```

**Generate for specific host:**
```bash
task ansible:generate-config HOSTNAME=storage
```

**Generate for specific group:**
```bash
task ansible:generate-config GROUPNAME=webui
```

**Note:** Cannot specify both `HOSTNAME` and `GROUPNAME` at the same time.

**How it works:**
1. Finds `*.yml` files in `files/group_config/` and/or `files/host_config/`
2. For each file, creates corresponding directory in `inventory/group_vars/` or `inventory/host_vars/`
3. Runs `op inject` to resolve secret references
4. Writes output to `99-config.secret.yml` omitting comment lines

## Requirements

Install Ansible Galaxy collections and roles:
```bash
ansible-galaxy install -r requirements.yaml
```

## Best Practices

1. **Never commit secrets** - Use 1Password references in `group_config` and `host_config` files
2. **Regenerate after changes** - Run `task ansible:generate-config` after modifying config files
3. **Use groups wisely** - Define shared variables in `group_config`, host-specific in `host_config`
4. **Use tags** - Run specific parts of playbooks with `--tags`
5. **Fail fast** - Include validation tasks in playbooks to catch misconfigurations early
