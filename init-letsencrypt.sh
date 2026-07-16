#!/bin/bash

# ==============================================================================
# .env переменные:
#   DOMAIN         - доменное имя*
#   EMAIL          - email для Let's Encrypt
#   STAGING        - 1 для тестового режима
#   CF_Token       - Cloudflare API Token
#   CF_Account_ID  - Cloudflare Account ID (опционально)
# ==============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# --- Проверка .env -----------------------------------------------------------
if [ ! -e ".env" ]; then
    echo -e "${RED}❌  Файл .env не найден. Создайте его перед запуском.${NC}"
    exit 1
fi

set -a
source .env
set +a

# --- Параметры ---------------------------------------------------------------
staging="${STAGING:-0}"
data_path="./acme/data"
certs_path="./certs"
domain_name="${DOMAIN:-}"
email="${EMAIL:-}"
cf_token="${CF_Token:-}"
cf_account_id="${CF_Account_ID:-}"

if [ -z "$domain_name" ]; then
    echo -e "${RED}❌  Переменная DOMAIN не задана в .env${NC}"
    exit 1
fi

cert_path="$certs_path/live/$domain_name/fullchain.pem"

# ==============================================================================
# Туториал
# ==============================================================================
print_cloudflare_tutorial() {
    echo ""
    echo -e "${CYAN}${BOLD}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}${BOLD}║        Как получить Cloudflare API Token                     ║${NC}"
    echo -e "${CYAN}${BOLD}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${BOLD}Шаг 1.${NC} Откройте в браузере:"
    echo -e "       ${YELLOW}https://dash.cloudflare.com/profile/api-tokens${NC}"
    echo ""
    echo -e "${BOLD}Шаг 2.${NC} Нажмите кнопку ${BOLD}«Create Token»${NC}"
    echo ""
    echo -e "${BOLD}Шаг 3.${NC} Выберите шаблон ${BOLD}«Edit zone DNS»${NC} → нажмите"
    echo -e "       ${BOLD}«Use template»${NC}"
    echo ""
    echo -e "${BOLD}Шаг 4.${NC} В разделе ${BOLD}«Zone Resources»${NC} выберите:"
    echo -e "       Include → Specific zone → ${YELLOW}$domain_name${NC}"
    echo -e "       ${CYAN}(это ограничит токен только вашим доменом - более безопасно)${NC}"
    echo ""
    echo -e "${BOLD}Шаг 5.${NC} Нажмите ${BOLD}«Continue to summary»${NC} → ${BOLD}«Create Token»${NC}"
    echo ""
    echo -e "${BOLD}Шаг 6.${NC} ${RED}Скопируйте токен сразу - он показывается только один раз!${NC}"
    echo ""
    echo -e "${CYAN}──────────────────────────────────────────────────────────────${NC}"
    echo -e "${CYAN}  ⚠️  Используйте API Token, а не Global API Key -${NC}"
    echo -e "${CYAN}      он имеет ограниченные права и безопаснее.${NC}"
    echo -e "${CYAN}──────────────────────────────────────────────────────────────${NC}"
    echo ""
}

# ==============================================================================
# Настройка Cloudflare токена
# ==============================================================================
setup_cloudflare() {
    if [ -n "$cf_token" ]; then
        return 0
    fi

    print_cloudflare_tutorial
    while true; do
        read -rp "$(echo -e "${BOLD}Вставьте Cloudflare API Token:${NC} ")" cf_token
        if [ -n "$cf_token" ]; then
            break
        fi
        echo -e "${RED}  Токен не может быть пустым. Попробуйте ещё раз.${NC}"
    done

    if grep -q "^CF_Token=" .env; then
        sed -i "s|^CF_Token=.*|CF_Token=$cf_token|" .env
    else
        echo "" >> .env
        echo "CF_Token=$cf_token" >> .env
    fi
    echo -e "${GREEN}  ✓ CF_Token сохранён в .env${NC}"
    echo ""
}

echo ""
echo -e "${BOLD}### Проверка Cloudflare API Token ...${NC}"
setup_cloudflare

# ==============================================================================
# Проверка существующего сертификата
# ==============================================================================
cert_is_valid() {
    [ -f "$cert_path" ] || return 1
    openssl x509 -in "$cert_path" -noout 2>/dev/null || return 1
    openssl x509 -in "$cert_path" -noout -checkend 0 2>/dev/null || return 1
    openssl x509 -in "$cert_path" -noout -issuer 2>/dev/null | grep -qi "let.s encrypt" || return 1
    return 0
}

if cert_is_valid; then
    expiry=$(openssl x509 -in "$cert_path" -noout -enddate 2>/dev/null | cut -d= -f2)
    echo -e "${GREEN}✅  Действительный сертификат Let's Encrypt для $domain_name уже существует.${NC}"
    echo -e "    Срок действия до: ${BOLD}$expiry${NC}"
    echo ""
    read -rp "$(echo -e "    Использовать существующий сертификат? (Y/n) ")" decision
    decision="${decision:-Y}"
    if [[ "$decision" =~ ^[Yy]$ ]]; then
        echo ""
        echo "### Запуск сервисов с существующим сертификатом ..."
        docker compose up --force-recreate -d
        echo ""
        echo -e "${GREEN}✅  Готово - сертификат применён.${NC}"
        exit 0
    fi
    echo ""
    echo -e "${YELLOW}ℹ️   Принудительный перевыпуск...${NC}"
fi

# ==============================================================================
# TLS-параметры
# ==============================================================================
if [ ! -e "$certs_path/options-ssl-nginx.conf" ] || \
   [ ! -e "$certs_path/ssl-dhparams.pem" ]; then
    echo ""
    echo "### Копирование рекомендуемых TLS-параметров ..."
    mkdir -p "$certs_path"
    cp "$(dirname "$0")/nginx/tls/options-ssl-nginx.conf" "$certs_path/options-ssl-nginx.conf"
    cp "$(dirname "$0")/nginx/tls/ssl-dhparams.pem" "$certs_path/ssl-dhparams.pem"
fi

mkdir -p "$data_path" "$certs_path/live/$domain_name"

# ==============================================================================
# Аргументы acme.sh
# ==============================================================================
email_arg=""
if [ -n "$email" ]; then
    email_arg="--accountemail $email"
fi

staging_arg=""
if [ "$staging" != "0" ]; then
    staging_arg="--staging"
    echo -e "${YELLOW}⚠️   Режим staging включён - браузеры не будут доверять сертификату.${NC}"
    echo ""
fi

# ==============================================================================
# Выпуск сертификата через DNS-01 (Cloudflare)
# ==============================================================================
echo "### Запрос сертификата Let's Encrypt (DNS-01, Cloudflare) для $domain_name ..."
echo ""

docker compose run --rm \
  -e CF_Token="$cf_token" \
  -e CF_Account_ID="$cf_account_id" \
  --entrypoint sh acme -c "
    acme.sh --issue \
      --dns dns_cf \
      -d '$domain_name' \
      -d 'www.$domain_name' \
      $staging_arg \
      $email_arg \
      --home /acme.sh \
      --force \
    && acme.sh --install-cert -d '$domain_name' \
      --home /acme.sh \
      --fullchain-file /certs/live/$domain_name/fullchain.pem \
      --key-file /certs/live/$domain_name/privkey.pem
  "

echo ""
echo "### Запуск сервисов ..."
docker compose up --force-recreate -d
echo ""
echo -e "${GREEN}✅  Сертификат успешно выпущен и применён для $domain_name${NC}"
