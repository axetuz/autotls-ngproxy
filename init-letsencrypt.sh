#!/bin/bash

# ==============================================================================
# .env переменные:
#   DOMAIN              - доменное имя*
#   EMAIL               - email для Let's Encrypt
#   STAGING             - 1 для тестового режима
#   CF_API_TOKEN        - Cloudflare API Token
#   DNS_PLUGIN          - имя плагина: dns-cloudflare, dns-route53 и др.
#   DNS_CREDENTIALS     - путь к credentials внутри контейнера
#   DNS_PROPAGATION_SEC - время ожидания распространения DNS, сек (по умолч. 60)
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
rsa_key_size=4096
data_path="./certbot"
domain_name="${DOMAIN:-}"
email="${EMAIL:-}"
cf_api_token="${CF_API_TOKEN:-}"
dns_plugin="${DNS_PLUGIN:-}"
dns_credentials="${DNS_CREDENTIALS:-}"
dns_propagation="${DNS_PROPAGATION_SEC:-60}"

if [ -z "$domain_name" ]; then
    echo -e "${RED}❌  Переменная DOMAIN не задана в .env${NC}"
    exit 1
fi

cert_path="$data_path/conf/live/$domain_name/fullchain.pem"

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
# Настройка Cloudflare credentials
# ==============================================================================
setup_cloudflare() {
    local secrets_dir="./certbot/secrets"
    local cf_ini="$secrets_dir/cloudflare.ini"
    local cf_ini_container="/secrets/cloudflare.ini"

    if [ -f "$cf_ini" ] && [ -z "$cf_api_token" ]; then
        echo -e "${GREEN}✅  Файл credentials Cloudflare уже существует: $cf_ini${NC}"
        dns_plugin="dns-cloudflare"
        dns_credentials="$cf_ini_container"
        return 0
    fi

    if [ -z "$cf_api_token" ]; then
        print_cloudflare_tutorial
        while true; do
            read -rp "$(echo -e "${BOLD}Вставьте Cloudflare API Token:${NC} ")" cf_api_token
            if [ -n "$cf_api_token" ]; then
                break
            fi
            echo -e "${RED}  Токен не может быть пустым. Попробуйте ещё раз.${NC}"
        done

        if grep -q "^CF_API_TOKEN=" .env; then
            sed -i "s|^CF_API_TOKEN=.*|CF_API_TOKEN=$cf_api_token|" .env
        else
            echo "" >> .env
            echo "CF_API_TOKEN=$cf_api_token" >> .env
        fi
        echo -e "${GREEN}  ✓ CF_API_TOKEN сохранён в .env${NC}"
    fi

    mkdir -p "$secrets_dir"
    cat > "$cf_ini" <<EOF
# Cloudflare API Token (Edit zone DNS)
# Получить: https://dash.cloudflare.com/profile/api-tokens
dns_cloudflare_api_token = $cf_api_token
EOF
    chmod 600 "$cf_ini"
    echo -e "${GREEN}  ✓ Файл credentials создан: $cf_ini (chmod 600)${NC}"

    if grep -q "^DNS_PLUGIN=" .env; then
        sed -i "s|^DNS_PLUGIN=.*|DNS_PLUGIN=dns-cloudflare|" .env
    else
        echo "DNS_PLUGIN=dns-cloudflare" >> .env
    fi
    if grep -q "^DNS_CREDENTIALS=" .env; then
        sed -i "s|^DNS_CREDENTIALS=.*|DNS_CREDENTIALS=$cf_ini_container|" .env
    else
        echo "DNS_CREDENTIALS=$cf_ini_container" >> .env
    fi
    echo -e "${GREEN}  ✓ DNS_PLUGIN и DNS_CREDENTIALS обновлены в .env${NC}"
    echo ""

    dns_plugin="dns-cloudflare"
    dns_credentials="$cf_ini_container"
}

# ==============================================================================
# Определить режим DNS и настроить credentials
# ==============================================================================
echo ""
echo -e "${BOLD}### Определение DNS-провайдера ...${NC}"

if [ -n "$cf_api_token" ] || \
   [ "${dns_plugin:-}" = "dns-cloudflare" ] || \
   [ -f "./certbot/secrets/cloudflare.ini" ]; then
    echo -e "    Провайдер: ${CYAN}Cloudflare${NC}"
    setup_cloudflare
elif [ -n "$dns_plugin" ] && [ -n "$dns_credentials" ]; then
    echo -e "    Провайдер: ${CYAN}$dns_plugin${NC} (из .env)"
else
    echo -e "    Провайдер: ${YELLOW}ручная верификация${NC}"
    echo ""
fi

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

skip_dummy=false

if cert_is_valid; then
    expiry=$(openssl x509 -in "$cert_path" -noout -enddate 2>/dev/null | cut -d= -f2)
    echo -e "${GREEN}✅  Действительный сертификат Let's Encrypt для $domain_name уже существует.${NC}"
    echo -e "    Срок действия до: ${BOLD}$expiry${NC}"
    echo ""
    read -rp "$(echo -e "    Использовать существующий сертификат? (Y/n) ")" decision
    decision="${decision:-Y}"
    if [[ "$decision" =~ ^[Yy]$ ]]; then
        echo ""
        echo "### Запуск nginx с существующим сертификатом ..."
        docker compose up --force-recreate -d nginx
        echo ""
        echo "### Перезагрузка конфигурации nginx ..."
        docker compose exec nginx nginx -s reload
        echo ""
        echo -e "${GREEN}✅  Готово - сертификат применён.${NC}"
        exit 0
    fi
    echo ""
    echo -e "${YELLOW}ℹ️   Принудительный перевыпуск...${NC}"
    skip_dummy=true
fi

# ==============================================================================
# TLS-параметры
# ==============================================================================
if [ ! -e "$data_path/conf/options-ssl-nginx.conf" ] || \
   [ ! -e "$data_path/conf/ssl-dhparams.pem" ]; then
    echo ""
    echo "### Загрузка рекомендуемых TLS-параметров ..."
    mkdir -p "$data_path/conf"
    curl -s \
      https://raw.githubusercontent.com/certbot/certbot/master/certbot-nginx/certbot_nginx/_internal/tls_configs/options-ssl-nginx.conf \
      > "$data_path/conf/options-ssl-nginx.conf"
    curl -s \
      https://raw.githubusercontent.com/certbot/certbot/master/certbot/certbot/ssl-dhparams.pem \
      > "$data_path/conf/ssl-dhparams.pem"
fi

# ==============================================================================
# Dummy сертификат
# ==============================================================================
if [ "$skip_dummy" = false ]; then
    echo ""
    echo "### Создание временного (dummy) сертификата для $domain_name ..."
    letsencrypt_path="/etc/letsencrypt/live/$domain_name"
    mkdir -p "$data_path/conf/live/$domain_name"
    docker compose run --rm --entrypoint "\
      openssl req -x509 -nodes -newkey rsa:$rsa_key_size -days 1 \
        -keyout '$letsencrypt_path/privkey.pem' \
        -out '$letsencrypt_path/fullchain.pem' \
        -subj '/CN=localhost'" certbot
    echo ""

    echo "### Запуск nginx с dummy-сертификатом ..."
    docker compose up --force-recreate -d nginx
    echo ""

    echo "### Удаление dummy-сертификата ..."
    docker compose run --rm --entrypoint "\
      rm -Rf /etc/letsencrypt/live/$domain_name \
             /etc/letsencrypt/archive/$domain_name \
             /etc/letsencrypt/renewal/$domain_name.conf" certbot
    echo ""
else
    echo ""
    echo "### Перезапуск nginx ..."
    docker compose up --force-recreate -d nginx
    echo ""
fi

# ==============================================================================
# Аргументы certbot
# ==============================================================================
case "$email" in
  "") email_arg="--register-unsafely-without-email" ;;
  *)  email_arg="-m $email" ;;
esac

staging_arg=""
if [ "$staging" != "0" ]; then
    staging_arg="--staging"
    echo -e "${YELLOW}⚠️   Режим staging включён - браузеры не будут доверять сертификату.${NC}"
    echo ""
fi

# ==============================================================================
# DNS challenge
# ==============================================================================
echo "### Запрос сертификата Let's Encrypt (DNS challenge) для $domain_name ..."
echo ""

if [ -n "$dns_plugin" ] && [ -n "$dns_credentials" ]; then
    echo -e "    Режим: ${CYAN}автоматический плагин [$dns_plugin]${NC}"
    echo -e "    Credentials: $dns_credentials"
    echo -e "    Ожидание распространения DNS: ${dns_propagation}с"
    echo ""
    docker compose run --rm --entrypoint "\
      certbot certonly \
        --$dns_plugin \
        --${dns_plugin}-credentials $dns_credentials \
        --${dns_plugin}-propagation-seconds $dns_propagation \
        $staging_arg \
        $email_arg \
        -d $domain_name \
        --rsa-key-size $rsa_key_size \
        --agree-tos \
        --force-renewal \
        --non-interactive" certbot
else
    echo -e "    Режим: ${YELLOW}ручная DNS верификация${NC}"
    echo ""
    echo -e "    Certbot попросит добавить TXT-запись:"
    echo -e "    ${BOLD}_acme-challenge.$domain_name${NC} → <значение от certbot>"
    echo -e "    После добавления записи нажмите ${BOLD}Enter${NC} для продолжения."
    echo ""
    docker compose run -it --rm --entrypoint "\
      certbot certonly \
        --manual \
        --preferred-challenges dns \
        $staging_arg \
        $email_arg \
        -d $domain_name \
        --rsa-key-size $rsa_key_size \
        --agree-tos \
        --force-renewal" certbot
fi

echo ""
echo "### Перезагрузка nginx с новым сертификатом ..."
docker compose exec nginx nginx -s reload
echo ""
echo -e "${GREEN}✅  Сертификат успешно выпущен и применён для $domain_name${NC}"