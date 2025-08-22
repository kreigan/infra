## Host configuration source

Each host to be managed can have a corresponding YAML configuration file in 
`ansible/files/host_config/`. Files are named after the host names in the inventory and
have a `.yml` extension. E.g. `storage.yml`.

Inside, you can define variables specific to that host.

## Tasks (Taskfile)

### generate-config

Use to generate host variable files using the `host_config` directory. It is especially
useful to reference 1Password secrets instead of hardcoding sensitive information or
manually creating env files.
See [Secret reference syntax](https://developer.1password.com/docs/cli/secret-reference-syntax/).

The task looks for `*.yml` files in the `files/host_config` directory. For each found
file, it creates a directory with the file name (without extension) in
`inventory/host_vars/` and puts there the contents of the original file. Right now,
the destination file name is hardcoded as `99-config.secret.yml`. Such files are ignored
by Git.

The task can run for a single host by specifying the host name as an argument:

```bash
HOSTNAME=myhost task ansible:generate-config
```

or

```bash
task ansible:generate-config HOSTNAME=myhost
```
