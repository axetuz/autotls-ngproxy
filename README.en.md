# autotls-ngproxy

[ 🇬🇧 English ] [ [🇷🇺 Русский](README.md) ]

Reverse proxy on nginx with automatic issuance and renewal of Let's Encrypt TLS certificates via acme.sh (DNS-01, Cloudflare)

## Environment variables (.env)

| Variable               | Required | Description                                                        |
|------------------------|:--------:|----------------------------------------------------------------------|
| `DOMAIN`               | yes      | Domain the certificate is issued for                                 |
| `PROXY_PASS`           | yes      | Upstream service address (`http://host:port`)                        |
| `EMAIL`                | no       | Email for Let's Encrypt registration                                 |
| `STAGING`               | no       | `1` — use LE staging environment (for testing), `0` — production     |
| `CF_Token`             | yes      | Cloudflare API token (Edit zone DNS) used for DNS-01 issuance        |
| `CF_Account_ID`        | no       | Cloudflare Account ID (required for some token types)                |

## First run

1. Fill in `.env`.
2. Issue the certificate:

   ```bash
   ./init-letsencrypt.sh
   ```

   The script creates `acme/data`, `certs` and obtains the
   certificate via DNS-01 (Cloudflare) using acme.sh.

3. Bring up the services:

   ```bash
   docker compose up -d
   ```

## Migrating from certbot to acme.sh

If you already have an older deployment running (certbot, `.env`
with `CF_API_TOKEN`/`DNS_PLUGIN`), run:

```bash
./migrate-to-acmesh.sh
```

The script stops the old services, migrates `.env` to the new
variables (`CF_Token`, `CF_Account_ID`), copies the existing
certificate from `./certbot/conf` to `./certs` if present, and
runs `./init-letsencrypt.sh`.

## Services

- **nginx** — terminates TLS, proxies requests to `PROXY_PASS`,
  reloads the config every 6 hours (`nginx -s reload`) to pick up
  a renewed certificate.
- **acme** — calls `acme.sh --cron` every 12 hours to renew the
  certificate and refresh files in `./certs`.

## Updating configuration

If you change `DOMAIN` or `PROXY_PASS` in `.env`, just restart the
nginx container — the template will be re-rendered:

```bash
docker compose restart nginx
```

## License

[MIT](LICENSE)
