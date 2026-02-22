# Caddy Role

Builds, deploys, and configures Caddy reverse proxy with Cloudflare DNS support.
Optionally may include additional xcaddy modules.

Caddy configuration is provided via the `caddy_config` variable in YAML format
that is converted to JSON for Caddy.

Cloudflare API token is provided via the `caddy_cf_api_token` variable.

## Prerequisites

- Go and xcaddy installed on localhost
- Cloudflare API token with DNS edit permissions

## Usage

### Playbook

```yaml
- name: Deploy gateway
  hosts: gateway01
  roles:
    - role: caddy
      vars:
        caddy_cf_api_token: 1234567890abcdef1234567890abcdef123
        caddy_config:
          apps:
            http:
              servers:
                myserver:
                  listen: [":80", ":443"]
                  routes:
                    - match:
                        - host: ["example.com"]
                      handle:
                        - handler: reverse_proxy
                          upstreams:
                            - dial: my_backend:8080
```

Run the playbook as usual:
```bash
ansible-playbook -i inventory gateway.yml
```

Selective execution:
- Deploy only: `--tags deploy`
- Config only: `--tags config`

## Tags

- `deploy`: Build and deploy Caddy, create systemd service
- `config`: Configure Caddy, manage credentials, reload service
