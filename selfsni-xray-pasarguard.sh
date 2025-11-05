#!/bin/bash
# Мастер-скрипт для установки Self SNI + Pasarguard Node + Xray
# 
# Использование:
#   bash selfsni-xray-pasarguard.sh
# 
# Или через GitHub (замените USER/REPO на ваш репозиторий):
#   bash <(curl -Ls https://raw.githubusercontent.com/USER/REPO/main/pasarguard-node-conf/selfsni-xray-pasarguard.sh)

set -e

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# Функции для цветного вывода
info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }
step() { echo -e "${MAGENTA}[STEP]${NC} $1"; }

# Проверка root прав
if [ "$EUID" -ne 0 ]; then 
    error "Пожалуйста, запустите скрипт от имени root (sudo)"
    exit 1
fi

# Проверка ОС
if ! grep -E -q "^(ID=debian|ID=ubuntu)" /etc/os-release; then
    error "Скрипт поддерживает только Debian или Ubuntu"
    exit 1
fi

info "=========================================="
info "  Установка Self SNI + Pasarguard Node"
info "=========================================="
echo ""

# Шаг 1: Запрос домена
step "Шаг 1: Настройка домена для Self SNI"
read -p "Введите доменное имя для Self SNI (например: ses-1.onesuper.ru): " DOMAIN
if [[ -z "$DOMAIN" ]]; then
    error "Доменное имя не может быть пустым"
    exit 1
fi

if [[ ! "$DOMAIN" =~ ^[a-zA-Z0-9][a-zA-Z0-9\.-]*[a-zA-Z0-9]$ ]]; then
    error "Неверный формат домена: $DOMAIN"
    exit 1
fi

success "Домен: $DOMAIN"
echo ""

# Шаг 2: Запрос порта для Pasarguard Node
step "Шаг 2: Настройка порта для Pasarguard Node"
read -p "Введите порт для Pasarguard Node (по умолчанию 62050): " PASARGUARD_PORT
if [[ -z "$PASARGUARD_PORT" ]]; then
    PASARGUARD_PORT=62050
fi

if ! [[ "$PASARGUARD_PORT" =~ ^[0-9]+$ ]] || [ "$PASARGUARD_PORT" -lt 1 ] || [ "$PASARGUARD_PORT" -gt 65535 ]; then
    error "Неверный порт: $PASARGUARD_PORT (должен быть от 1 до 65535)"
    exit 1
fi

if command -v ss &>/dev/null; then
    if ss -tlnp | grep -q ":${PASARGUARD_PORT} "; then
        error "Порт $PASARGUARD_PORT уже занят"
        exit 1
    fi
fi

success "Порт Pasarguard Node: $PASARGUARD_PORT"
echo ""

# Шаг 3: Проверка портов 80 и 443
step "Шаг 3: Проверка портов 80 и 443"
if ss -tlnp | grep -q ":443 "; then
    error "Порт 443 уже занят. Освободите порт перед установкой."
    exit 1
fi

if ss -tlnp | grep -q ":80 "; then
    warning "Порт 80 занят. Скрипт fakesite.sh может не работать."
    read -p "Продолжить установку? (y/n): " CONTINUE
    if [[ ! "$CONTINUE" =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

success "Порты проверены"
echo ""

# Шаг 4: Установка необходимых пакетов
step "Шаг 4: Установка необходимых пакетов"
apt update -qq
apt install -y curl wget git expect >/dev/null 2>&1
success "Пакеты установлены"
echo ""

# Шаг 5: Подготовка скриптов
step "Шаг 5: Подготовка скриптов"
SCRIPT_DIR="/tmp/selfsni-setup-$$"
mkdir -p "$SCRIPT_DIR"

SCRIPT_SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Определяем, откуда запущен скрипт
if [ -f "$SCRIPT_SOURCE_DIR/fakesite.sh" ] && [ -f "$SCRIPT_SOURCE_DIR/pg-node.sh" ]; then
    cp "$SCRIPT_SOURCE_DIR/fakesite.sh" "$SCRIPT_DIR/fakesite.sh"
    cp "$SCRIPT_SOURCE_DIR/pg-node.sh" "$SCRIPT_DIR/pg-node.sh"
    success "Скрипты найдены в $SCRIPT_SOURCE_DIR"
elif [ -f "./fakesite.sh" ] && [ -f "./pg-node.sh" ]; then
    cp ./fakesite.sh "$SCRIPT_DIR/fakesite.sh"
    cp ./pg-node.sh "$SCRIPT_DIR/pg-node.sh"
    success "Скрипты найдены в текущей директории"
else
    info "Скачивание скриптов с GitHub..."
    if ! curl -sL "https://raw.githubusercontent.com/YukiKras/vless-scripts/main/fakesite.sh" -o "$SCRIPT_DIR/fakesite.sh"; then
        error "Не удалось скачать fakesite.sh"
        rm -rf "$SCRIPT_DIR"
        exit 1
    fi
    if ! curl -sL "https://raw.githubusercontent.com/PasarGuard/scripts/main/pg-node.sh" -o "$SCRIPT_DIR/pg-node.sh"; then
        error "Не удалось скачать pg-node.sh"
        rm -rf "$SCRIPT_DIR"
        exit 1
    fi
    success "Скрипты скачаны"
fi

chmod +x "$SCRIPT_DIR/fakesite.sh"
chmod +x "$SCRIPT_DIR/pg-node.sh"
echo ""

# Шаг 6: Установка Self SNI (fakesite.sh)
step "Шаг 6: Установка Self SNI (nginx + SSL)"
info "Запуск fakesite.sh с доменом: $DOMAIN, порт: 443"

MODIFIED_FAKESITE="$SCRIPT_DIR/fakesite-modified.sh"
sed "s/read -p \"Введите доменное имя: \" DOMAIN/DOMAIN=\"$DOMAIN\"/" "$SCRIPT_DIR/fakesite.sh" > "$MODIFIED_FAKESITE"
chmod +x "$MODIFIED_FAKESITE"

cd "$SCRIPT_DIR"
if bash "$MODIFIED_FAKESITE" --selfsni-port 443; then
    success "Self SNI установлен"
    
    # Заменяем конфиг Nginx на правильный из GitHub
    info "Замена конфигурации Nginx на sni.conf из репозитория..."
    
    # Определяем URL репозитория (используем тот же, что и для скрипта)
    GITHUB_REPO="DANTECK-dev/fast-start-selfsni-pasarguar"
    GITHUB_BRANCH="refs/heads/main"
    SNI_CONF_URL="https://raw.githubusercontent.com/$GITHUB_REPO/$GITHUB_BRANCH/sni.conf"
    
    # Скачиваем sni.conf
    info "Скачивание sni.conf с GitHub..."
    if curl -sL "$SNI_CONF_URL" -o /tmp/sni.conf.tmp; then
        # Проверяем, что файл скачался (не пустой и не 404)
        if [ -s /tmp/sni.conf.tmp ] && ! grep -q "404: Not Found" /tmp/sni.conf.tmp; then
            # Заменяем домен в скачанном конфиге на введенный пользователем
            sed -i "s/ses-1.onesuper.ru/$DOMAIN/g" /tmp/sni.conf.tmp
            
            # Удаляем все старые конфиги с этим доменом (чтобы избежать конфликтов)
            info "Удаление старых конфигов с доменом $DOMAIN..."
            REMOVED_COUNT=0
            for old_conf in /etc/nginx/sites-enabled/*.conf; do
                if [ -f "$old_conf" ] && [ "$old_conf" != "/etc/nginx/sites-enabled/sni.conf" ]; then
                    # Проверяем, есть ли в конфиге этот домен
                    if grep -q "server_name.*$DOMAIN" "$old_conf" 2>/dev/null; then
                        # Также проверяем, слушает ли он на 443 (может быть старый конфиг от fakesite.sh)
                        if grep -q "listen.*443" "$old_conf" 2>/dev/null; then
                            BACKUP_NAME="/etc/nginx/sites-enabled/$(basename "$old_conf").backup.$(date +%Y%m%d-%H%M%S)"
                            cp "$old_conf" "$BACKUP_NAME"
                            rm -f "$old_conf"
                            info "Удален старый конфиг: $(basename "$old_conf") (бэкап: $(basename "$BACKUP_NAME"))"
                            REMOVED_COUNT=$((REMOVED_COUNT + 1))
                        fi
                    fi
                fi
            done
            
            if [ $REMOVED_COUNT -gt 0 ]; then
                success "Удалено $REMOVED_COUNT дублирующихся конфигов"
            else
                info "Дублирующиеся конфиги не найдены"
            fi
            
            # Создаем бэкап существующего sni.conf если есть
            if [ -f /etc/nginx/sites-enabled/sni.conf ]; then
                cp /etc/nginx/sites-enabled/sni.conf /etc/nginx/sites-enabled/sni.conf.backup.$(date +%Y%m%d-%H%M%S)
                info "Создан бэкап существующего sni.conf"
            fi
            
            # Копируем в sites-enabled
            cp /tmp/sni.conf.tmp /etc/nginx/sites-enabled/sni.conf
            chmod 644 /etc/nginx/sites-enabled/sni.conf
            rm -f /tmp/sni.conf.tmp
            
            # Проверка синтаксиса
            info "Проверка синтаксиса Nginx..."
            if nginx -t >/tmp/nginx-test.log 2>&1; then
                success "Синтаксис Nginx корректен"
                
                # Перезапускаем Nginx
                if systemctl restart nginx; then
                    sleep 2
                    # Проверяем, что сайт доступен
                    if curl -k -s -m 5 "https://127.0.0.1:443" -H "Host: $DOMAIN" >/dev/null 2>&1; then
                        success "Nginx конфигурация обновлена, сайт доступен на localhost:443"
                    else
                        warning "Nginx перезапущен, но сайт не отвечает на localhost:443"
                        warning "Проверьте SSL сертификат и логи: tail -f /var/log/nginx/error.log"
                    fi
                else
                    error "Ошибка перезапуска Nginx"
                    warning "Проверьте: systemctl status nginx"
                fi
            else
                error "Ошибка синтаксиса в sni.conf!"
                warning "Детали:"
                cat /tmp/nginx-test.log | tail -5
                warning "Восстановите бэкап, если нужно"
                rm -f /tmp/nginx-test.log
            fi
        else
            warning "sni.conf не найден или пустой на GitHub"
            warning "Используем существующую конфигурацию от fakesite.sh"
        fi
    else
        warning "Не удалось скачать sni.conf с GitHub"
        warning "Используем существующую конфигурацию от fakesite.sh"
    fi
else
    error "Ошибка при установке Self SNI"
    rm -rf "$SCRIPT_DIR"
    exit 1
fi
echo ""

# Шаг 7: Установка Pasarguard Node
step "Шаг 7: Установка Pasarguard Node"
info "Запуск pg-node.sh install с портом: $PASARGUARD_PORT"

if ! command -v expect &>/dev/null; then
    apt install -y expect >/dev/null 2>&1
fi

EXPECT_SCRIPT="$SCRIPT_DIR/pg-node-expect.exp"
cat > "$EXPECT_SCRIPT" <<'EXPEOF'
#!/usr/bin/expect -f
set timeout 600
set pasarguard_port [lindex $argv 0]
set script_path [lindex $argv 1]

spawn bash "$script_path" install --version latest

expect {
    -re "node is already installed" {
        exp_continue
    }
    -re "Do you want to override.*\\?.*\\(y/n\\)" {
        send "y\r"
        exp_continue
    }
    -re "Enter the SERVICE_PORT.*:" {
        send "$pasarguard_port\r"
        exp_continue
    }
    -re "Do you want to use your own public certificate.*\\(Y/n\\):" {
        send "n\r"
        exp_continue
    }
    -re "Enter additional SAN entries" {
        send "\r"
        exp_continue
    }
    -re "Enter your API Key.*:" {
        send "\r"
        exp_continue
    }
    -re "Do you want to use REST protocol instead.*\\(Y/n\\):" {
        send "n\r"
        exp_continue
    }
    "node is set up" {
        expect eof
    }
    "Aborted installation" {
        puts "Installation was aborted"
        exit 1
    }
    timeout {
        puts "Timeout waiting for installation"
        exit 1
    }
    eof
}

catch wait result
exit [lindex $result 3]
EXPEOF

chmod +x "$EXPECT_SCRIPT"

if expect -f "$EXPECT_SCRIPT" "$PASARGUARD_PORT" "$SCRIPT_DIR/pg-node.sh"; then
    success "Pasarguard Node установлен"
    
    sleep 2
    for ENV_FILE in "/opt/pg-node/.env" "/opt/node/.env"; do
        if [ -f "$ENV_FILE" ]; then
            if grep -q "^SERVICE_PORT" "$ENV_FILE"; then
                sed -i "s/^SERVICE_PORT *= *.*/SERVICE_PORT= ${PASARGUARD_PORT}/" "$ENV_FILE"
            else
                echo "SERVICE_PORT= ${PASARGUARD_PORT}" >> "$ENV_FILE"
            fi
            break
        fi
    done
else
    error "Ошибка при установке Pasarguard Node"
    warning "Попробуйте установить вручную: bash $SCRIPT_DIR/pg-node.sh install"
    warning "И укажите порт: $PASARGUARD_PORT"
fi
echo ""

# Шаг 8: Настройка Firewall (UFW)
step "Шаг 8: Настройка Firewall (UFW)"

if ! command -v ufw &>/dev/null; then
    info "Установка UFW..."
    apt install -y ufw >/dev/null 2>&1
fi

info "Сброс правил UFW..."
ufw --force reset >/dev/null 2>&1

info "Настройка правил по умолчанию..."
ufw default deny incoming >/dev/null 2>&1
ufw default allow outgoing >/dev/null 2>&1

info "Отключение ping (ICMP)..."
iptables-save > /tmp/iptables-backup-$$.rules 2>/dev/null || true
iptables -A INPUT -p icmp --icmp-type echo-request -j DROP 2>/dev/null || true
if command -v netfilter-persistent &>/dev/null; then
    netfilter-persistent save >/dev/null 2>&1 || true
elif [ -f /etc/iptables/rules.v4 ]; then
    iptables-save > /etc/iptables/rules.v4 2>/dev/null || true
fi
success "Ping отключен"

info "Открытие портов..."
ufw allow 443/tcp >/dev/null 2>&1
success "Порт 443 открыт (для Xray Reality)"

ufw allow 80/tcp >/dev/null 2>&1
success "Порт 80 открыт (для Let's Encrypt)"

ufw allow ${PASARGUARD_PORT}/tcp >/dev/null 2>&1
success "Порт $PASARGUARD_PORT открыт (для Pasarguard Node)"

info "Определение SSH порта..."
SSH_PORT=""
if command -v ss &>/dev/null; then
    SSH_PORT=$(ss -tlnp | grep -E 'sshd|:22 ' | head -1 | awk '{print $4}' | cut -d: -f2)
fi

if [ -z "$SSH_PORT" ]; then
    SSH_PORT=22
fi

ufw allow ${SSH_PORT}/tcp >/dev/null 2>&1
success "SSH порт $SSH_PORT открыт"
warning "ВАЖНО: Убедитесь, что вы подключены через порт $SSH_PORT!"

info "Включение UFW..."
echo "y" | ufw enable >/dev/null 2>&1 || true

success "Firewall настроен"
echo ""

# Шаг 9: Проверка установки
step "Шаг 9: Проверка установки"
echo ""

# Проверка Nginx
info "Проверка Nginx..."
if systemctl is-active --quiet nginx; then
    success "Nginx запущен"
    
    # Проверка портов
    if ss -tlnp | grep -q "127.0.0.1:443.*nginx"; then
        success "Nginx слушает на 127.0.0.1:443"
    else
        warning "Nginx НЕ слушает на 127.0.0.1:443"
        warning "Проверьте конфигурацию: nginx -t"
    fi
    
    # Проверка доступности сайта
    if curl -k -s -m 5 "https://127.0.0.1:443" -H "Host: $DOMAIN" >/dev/null 2>&1; then
        success "Сайт доступен на localhost:443"
    else
        warning "Сайт не отвечает на localhost:443"
        warning "Проверьте SSL сертификат и логи nginx"
    fi
else
    warning "Nginx не запущен"
    warning "Запустите: systemctl start nginx"
fi
echo ""

# Проверка SSL сертификата
info "Проверка SSL сертификата..."
CERT_PATH="/etc/letsencrypt/live/$DOMAIN/fullchain.pem"
if [ -f "$CERT_PATH" ]; then
    success "SSL сертификат найден: $CERT_PATH"
    EXPIRY=$(openssl x509 -enddate -noout -in "$CERT_PATH" 2>/dev/null | cut -d= -f2)
    echo "   Срок действия: $EXPIRY"
else
    error "SSL сертификат не найден: $CERT_PATH"
    warning "Получите сертификат: certbot certonly --webroot -w /var/www/html -d $DOMAIN"
fi
echo ""

# Проверка портов
info "Проверка портов..."
PORTS_OK=1
if ss -tlnp | grep -q "0.0.0.0:443.*xray"; then
    success "Xray слушает на 0.0.0.0:443"
elif ss -tlnp | grep -q ":443.*xray"; then
    warning "Xray слушает на порту 443, но не на 0.0.0.0"
    PORTS_OK=0
else
    warning "Xray НЕ слушает на 0.0.0.0:443"
    warning "Xray будет запущен через Pasarguard Panel"
    PORTS_OK=0
fi

if ss -tlnp | grep -q "127.0.0.1:443.*nginx"; then
    success "Nginx слушает на 127.0.0.1:443"
else
    warning "Nginx НЕ слушает на 127.0.0.1:443"
    PORTS_OK=0
fi
echo ""

info "=========================================="
success "  Установка завершена!"
info "=========================================="
echo ""
success "Домен: $DOMAIN"
success "Self SNI порт: 127.0.0.1:443"
success "Pasarguard Node порт: $PASARGUARD_PORT"
echo ""

info "Важные настройки для Pasarguard Panel:"
echo "  - Dest: 127.0.0.1:443"
echo "  - SNI: $DOMAIN"
echo "  - Service Port: $PASARGUARD_PORT"
echo "  - Используйте конфиг xray.json"
echo ""

info "Firewall настроен:"
echo "  - Ping (ICMP) отключен"
echo "  - Порт 443 открыт (Xray Reality)"
echo "  - Порт 80 открыт (Let's Encrypt)"
echo "  - Порт $PASARGUARD_PORT открыт (Pasarguard Node)"
echo "  - SSH порт $SSH_PORT открыт"
echo "  - Все остальные порты закрыты"
echo ""

warning "ВНИМАНИЕ: Убедитесь, что SSH порт открыт перед выходом из сессии!"
echo ""

info "КРИТИЧЕСКИ ВАЖНО: Порядок запуска сервисов!"
echo ""
echo "После настройки Xray в Pasarguard Panel:"
echo ""
echo "1. Остановите все сервисы:"
echo "   systemctl stop nginx"
echo "   pg-node down"
echo ""
echo "2. Запустите Nginx первым:"
echo "   systemctl start nginx"
echo ""
echo "3. Запустите Pasarguard Node (Xray):"
echo "   pg-node up"
echo "   или через Pasarguard Panel"
echo ""
echo "4. Проверьте порты:"
echo "   ss -tlnp | grep :443"
echo "   Должно быть:"
echo "   - Xray на 0.0.0.0:443"
echo "   - Nginx на 127.0.0.1:443"
echo ""

info "Следующие шаги:"
echo "  1. Настройте Xray в Pasarguard Panel:"
echo "     - Используйте xray.json"
echo "     - Dest: 127.0.0.1:443"
echo "     - SNI: $DOMAIN"
echo "     - Создайте хост (Freedom, tag: direct)"
echo ""
echo "  2. Проверьте работу:"
echo "     - curl https://$DOMAIN"
echo "     - systemctl status nginx"
echo ""
echo "  3. Если получаете ошибку 'REALITY: processed invalid connection':"
echo "     - Проверьте порядок запуска (см. выше)"
echo "     - Убедитесь, что Nginx запущен на 127.0.0.1:443"
echo "     - Убедитесь, что Xray запущен на 0.0.0.0:443"
echo "     - Проверьте логи: tail -f /var/log/xray/error.log"
echo ""

# Очистка временных файлов
info "Очистка временных файлов..."
rm -rf "$SCRIPT_DIR"
rm -f /tmp/iptables-backup-*.rules

success "=========================================="
success "  Установка полностью завершена!"
success "=========================================="

