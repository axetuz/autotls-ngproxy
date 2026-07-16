# autotls-ngproxy

[ [🇬🇧 English](README.en.md) ] [ 🇷🇺 Русский ]

Reverse proxy на nginx с автоматическим выпуском и обновлением TLS-сертификатов Let's Encrypt через acme.sh (DNS-01, Cloudflare)

## Переменные окружения (.env)

| Переменная            | Обязательна | Описание                                                        |
|------------------------|:-----------:|-------------------------------------------------------------------|
| `DOMAIN`               | да          | Домен, на который выпускается сертификат                          |
| `PROXY_PASS`           | да          | Адрес upstream-сервиса (`http://host:port`)                       |
| `EMAIL`                | нет         | Email для регистрации в Let's Encrypt                             |
| `STAGING`              | нет         | `1` — использовать staging-окружение LE (для тестов), `0` — прод   |
| `CF_Token`             | да          | API-токен Cloudflare (Edit zone DNS) для выпуска через DNS-01      |
| `CF_Account_ID`        | нет         | Cloudflare Account ID (нужен для некоторых типов токенов)          |

## Первый запуск

1. Заполнить `.env`.
2. Выпустить сертификат:

   ```bash
   ./init-letsencrypt.sh
   ```

   Скрипт сам создаёт `acme/data`, `certs` и получает сертификат
   через DNS-01 (Cloudflare) с помощью acme.sh.

3. Поднять сервисы:

   ```bash
   docker compose up -d
   ```

## Миграция с certbot на acme.sh

Если у вас уже развёрнута старая версия (certbot, `.env` с
`CF_API_TOKEN`/`DNS_PLUGIN`), выполните:

```bash
./migrate-to-acmesh.sh
```

Скрипт остановит старые сервисы, перенесёт `.env` на новые
переменные (`CF_Token`, `CF_Account_ID`), при наличии скопирует
существующий сертификат из `./certbot/conf` в `./certs` и запустит
`./init-letsencrypt.sh`.

## Сервисы

- **nginx** — терминирует TLS, проксирует запросы на `PROXY_PASS`,
  каждые 6 часов перечитывает конфиг (`nginx -s reload`), чтобы
  подхватить обновлённый сертификат.
- **acme** — раз в 12 часов вызывает `acme.sh --cron` для продления
  сертификата и обновляет файлы в `./certs`.

## Обновление конфигурации

При изменении `DOMAIN` или `PROXY_PASS` в `.env` достаточно
перезапустить контейнер nginx — шаблон будет отрендерен заново:

```bash
docker compose restart nginx
```

## Лицензия

[MIT](LICENSE)
