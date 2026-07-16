#!/bin/bash

# ==============================================================================
# Миграция окружения с certbot на acme.sh.
#
# Что делает скрипт:
#   1. Останавливает старые сервисы (certbot/nginx), если они запущены.
#   2. Переносит .env: CF_API_TOKEN -> CF_Token, удаляет устаревшие
#      DNS_PLUGIN/DNS_CREDENTIALS/DNS_PROPAGATION_SEC/CERTBOT_IMAGE.
#   3. Создаёт новые каталоги ./acme/data и ./certs.
#   4. Если найден старый сертификат в ./certbot/conf/live/$DOMAIN,
#      предлагает скопировать его в ./certs/live/$DOMAIN, чтобы не
#      выпускать новый сертификат прямо сейчас.
#   5. Удаляет старый каталог ./certbot (после подтверждения).
#   6. Запускает ./init-letsencrypt.sh для выпуска/применения сертификата
#      через acme.sh (можно пропустить, если сертификат уже скопирован).
# ==============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

old_data_path="./certbot"
new_data_path="./acme/data"
certs_path="./certs"

echo -e "${CYAN}${BOLD}=== Миграция autotls-ngproxy: certbot -> acme.sh ===${NC}"
echo ""

# --- Проверка .env -----------------------------------------------------------
if [ ! -e ".env" ]; then
    echo -e "${RED}❌  Файл .env не найден. Нечего мигрировать.${NC}"
    exit 1
fi

domain_name="$(grep -E '^DOMAIN=' .env | tail -n1 | cut -d= -f2-)"

if [ -z "$domain_name" ]; then
    echo -e "${RED}❌  Переменная DOMAIN не задана в .env${NC}"
    exit 1
fi

echo -e "    Домен: ${BOLD}$domain_name${NC}"
echo ""

# ==============================================================================
# 1. Остановка старых сервисов
# ==============================================================================
if command -v docker >/dev/null 2>&1 && docker compose ps --status running -q >/dev/null 2>&1; then
    running="$(docker compose ps --status running -q 2>/dev/null || true)"
    if [ -n "$running" ]; then
        echo "### Остановка запущенных сервисов ..."
        docker compose down
        echo ""
    fi
fi

# ==============================================================================
# 2. Перенос .env
# ==============================================================================
echo "### Обновление .env ..."

cp .env .env.bak
echo -e "    ${GREEN}✓ Резервная копия сохранена: .env.bak${NC}"

old_token="$(grep -E '^CF_API_TOKEN=' .env | tail -n1 | cut -d= -f2- || true)"

if [ -n "$old_token" ]; then
    if grep -q '^CF_Token=' .env; then
        sed -i "s|^CF_Token=.*|CF_Token=$old_token|" .env
    else
        echo "CF_Token=$old_token" >> .env
    fi
    echo -e "    ${GREEN}✓ CF_API_TOKEN перенесён в CF_Token${NC}"
fi

if ! grep -q '^CF_Account_ID=' .env; then
    echo "CF_Account_ID=" >> .env
fi

sed -i \
    -e '/^CF_API_TOKEN=/d' \
    -e '/^CERTBOT_IMAGE=/d' \
    -e '/^DNS_PLUGIN=/d' \
    -e '/^DNS_CREDENTIALS=/d' \
    -e '/^DNS_PROPAGATION_SEC=/d' \
    .env

echo -e "    ${GREEN}✓ Устаревшие переменные certbot удалены из .env${NC}"
echo ""

# ==============================================================================
# 3. Новые каталоги
# ==============================================================================
echo "### Создание каталогов acme.sh ..."
mkdir -p "$new_data_path" "$certs_path/live/$domain_name"
echo -e "    ${GREEN}✓ $new_data_path${NC}"
echo -e "    ${GREEN}✓ $certs_path/live/$domain_name${NC}"
echo ""

# ==============================================================================
# 4. Перенос существующего сертификата
# ==============================================================================
old_cert_dir="$old_data_path/conf/live/$domain_name"
old_fullchain="$old_cert_dir/fullchain.pem"
old_privkey="$old_cert_dir/privkey.pem"

if [ -f "$old_fullchain" ] && [ -f "$old_privkey" ]; then
    echo -e "${YELLOW}ℹ️   Найден существующий сертификат certbot для $domain_name.${NC}"
    read -rp "$(echo -e "    Скопировать его в $certs_path/live/$domain_name (без немедленного перевыпуска)? (Y/n) ")" copy_decision
    copy_decision="${copy_decision:-Y}"
    if [[ "$copy_decision" =~ ^[Yy]$ ]]; then
        cp -L "$old_fullchain" "$certs_path/live/$domain_name/fullchain.pem"
        cp -L "$old_privkey" "$certs_path/live/$domain_name/privkey.pem"
        echo -e "    ${GREEN}✓ Сертификат скопирован${NC}"
        skip_issue=true
    else
        skip_issue=false
    fi
else
    echo -e "${YELLOW}ℹ️   Существующий сертификат certbot не найден - потребуется новый выпуск.${NC}"
    skip_issue=false
fi
echo ""

if [ -f "$old_data_path/conf/options-ssl-nginx.conf" ]; then
    cp "$old_data_path/conf/options-ssl-nginx.conf" "$certs_path/options-ssl-nginx.conf"
fi
if [ -f "$old_data_path/conf/ssl-dhparams.pem" ]; then
    cp "$old_data_path/conf/ssl-dhparams.pem" "$certs_path/ssl-dhparams.pem"
fi

# ==============================================================================
# 5. Удаление старого каталога certbot
# ==============================================================================
if [ -d "$old_data_path" ]; then
    read -rp "$(echo -e "${BOLD}Удалить старый каталог $old_data_path? (y/N) ${NC}")" rm_decision
    rm_decision="${rm_decision:-N}"
    if [[ "$rm_decision" =~ ^[Yy]$ ]]; then
        rm -rf "$old_data_path"
        echo -e "    ${GREEN}✓ $old_data_path удалён${NC}"
    else
        echo -e "    ${YELLOW}ℹ️   $old_data_path оставлен без изменений${NC}"
    fi
    echo ""
fi

# ==============================================================================
# 6. Выпуск/применение сертификата через acme.sh
# ==============================================================================
echo -e "${CYAN}${BOLD}=== Миграция .env и данных завершена ===${NC}"
echo ""

if [ "${skip_issue:-false}" = true ]; then
    echo -e "${GREEN}Сертификат перенесён без перевыпуска.${NC}"
    read -rp "$(echo -e "Всё равно запустить ./init-letsencrypt.sh для проверки/применения? (y/N) ")" run_decision
    run_decision="${run_decision:-N}"
    if [[ ! "$run_decision" =~ ^[Yy]$ ]]; then
        echo ""
        echo "### Запуск сервисов с перенесённым сертификатом ..."
        docker compose up --force-recreate -d
        echo ""
        echo -e "${GREEN}✅  Готово.${NC}"
        exit 0
    fi
fi

echo "### Запуск ./init-letsencrypt.sh ..."
echo ""
exec ./init-letsencrypt.sh
