# autotls-ngproxy

[ [🇬🇧 English](README.en.md) ] [ 🇷🇺 Русский ]

Reverse proxy на nginx с автоматическим выпуском и обновлением TLS-сертификатов Let's Encrypt через certbot (DNS-01, Cloudflare по умолчанию)

## Переменные окружения (.env)

| Переменная            | Обязательна | Описание                                                        |
|------------------------|:-----------:|-------------------------------------------------------------------|
| `DOMAIN`               | да          | Домен, на который выпускается сертификат                          |
| `PROXY_PASS`           | да          | Адрес upstream-сервиса (`http://host:port`)                       |
| `EMAIL`                | да          | Email для регистрации в Let's Encrypt                             |
| `STAGING`              | нет         | `1` — использовать staging-окружение LE (для тестов), `0` — прод   |
| `CERTBOT_IMAGE`        | нет         | Образ certbot, по умолчанию `certbot/certbot`. Для DNS-01 нужен образ с нужным плагином, например `certbot/dns-cloudflare` |
| `DNS_PLUGIN`           | нет         | Имя плагина certbot (`dns-cloudflare`, `dns-route53`, ...)         |
| `DNS_CREDENTIALS`      | нет         | Путь внутри контейнера к файлу с учётными данными DNS-провайдера   |
| `DNS_PROPAGATION_SEC`  | нет         | Время ожидания распространения DNS-записи перед проверкой (сек)    |
| `CF_API_TOKEN`         | нет*        | API-токен Cloudflare (для `dns-cloudflare`)                        |

\* обязательна, если используется DNS-плагин Cloudflare.

## Первый запуск

1. Заполнить `.env`.
2. Выпустить сертификат:

   ```bash
   ./init-letsencrypt.sh
   ```

   Скрипт сам создаёт `certbot/conf`, `certbot/secrets` и получает
   сертификат через DNS-01 (или webroot, в зависимости от настроек).

3. Поднять сервисы:

   ```bash
   docker compose up -d
   ```

## Сервисы

- **nginx** — терминирует TLS, проксирует запросы на `PROXY_PASS`,
  каждые 6 часов перечитывает конфиг (`nginx -s reload`), чтобы
  подхватить обновлённый сертификат.
- **certbot** — раз в 12 часов вызывает `certbot renew` для продления
  сертификата.

## Обновление конфигурации

При изменении `DOMAIN` или `PROXY_PASS` в `.env` достаточно
перезапустить контейнер nginx — шаблон будет отрендерен заново:

```bash
docker compose restart nginx
```

## Лицензия

[MIT](LICENSE)
