# autotls-ngproxy

[ 🇬🇧 English ] [ [🇷🇺 Русский](README.md) ]

Reverse proxy on nginx with automatic issuance and renewal of Let's Encrypt TLS certificates via certbot (DNS-01, Cloudflare by default)

## Environment variables (.env)

| Variable               | Required | Description                                                        |
|------------------------|:--------:|----------------------------------------------------------------------|
| `DOMAIN`               | yes      | Domain the certificate is issued for                                 |
| `PROXY_PASS`           | yes      | Upstream service address (`http://host:port`)                        |
| `EMAIL`                | yes      | Email for Let's Encrypt registration                                 |
| `STAGING`               | no       | `1` — use LE staging environment (for testing), `0` — production     |
| `CERTBOT_IMAGE`        | no       | Certbot image, defaults to `certbot/certbot`. DNS-01 needs an image with the right plugin, e.g. `certbot/dns-cloudflare` |
| `DNS_PLUGIN`           | no       | Certbot plugin name (`dns-cloudflare`, `dns-route53`, ...)           |
| `DNS_CREDENTIALS`      | no       | Path inside the container to the DNS provider credentials file       |
| `DNS_PROPAGATION_SEC`  | no       | Time to wait for DNS propagation before verification (sec)           |
| `CF_API_TOKEN`         | no*      | Cloudflare API token (for `dns-cloudflare`)                          |

\* required if the Cloudflare DNS plugin is used.

## First run

1. Fill in `.env`.
2. Issue the certificate:

   ```bash
   ./init-letsencrypt.sh
   ```

   The script creates `certbot/conf`, `certbot/secrets` and obtains
   the certificate via DNS-01 (or webroot, depending on settings).

3. Bring up the services:

   ```bash
   docker compose up -d
   ```

## Services

- **nginx** — terminates TLS, proxies requests to `PROXY_PASS`,
  reloads the config every 6 hours (`nginx -s reload`) to pick up
  a renewed certificate.
- **certbot** — calls `certbot renew` every 12 hours to renew the
  certificate.

## Updating configuration

If you change `DOMAIN` or `PROXY_PASS` in `.env`, just restart the
nginx container — the template will be re-rendered:

```bash
docker compose restart nginx
```

## License

[MIT](LICENSE)
