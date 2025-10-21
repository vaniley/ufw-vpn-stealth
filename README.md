#!/bin/bash

##
# Цветовые переменные
##
GREEN='\e[32m'
BLUE='\e[34m'
RED='\e[31m'
YELLOW='\e[33m'
CYAN='\e[36m'
CLEAR='\e[0m'

##
# Цветовые функции
##
ColorGreen(){
    echo -ne "${GREEN}$1${CLEAR}"
}

ColorBlue(){
    echo -ne "${BLUE}$1${CLEAR}"
}

ColorRed(){
    echo -ne "${RED}$1${CLEAR}"
}

ColorYellow(){
    echo -ne "${YELLOW}$1${CLEAR}"
}

ColorCyan(){
    echo -ne "${CYAN}$1${CLEAR}"
}

##
# Проверка root прав
##
check_root() {
    if [ "$EUID" -ne 0 ]; then 
        echo -e "$(ColorRed '❌ Ошибка: Скрипт должен быть запущен с правами root!')"
        echo -e "$(ColorYellow 'Используйте: sudo ./script.sh')"
        exit 1
    fi
}

##
# Создание бэкапа
##
backup_config() {
    BACKUP_FILE="/etc/ufw/before.rules.backup_$(date +%Y%m%d_%H%M%S)"
    cp /etc/ufw/before.rules "$BACKUP_FILE"
    echo -e "$(ColorGreen '✓ Бэкап создан:') $BACKUP_FILE"
}

##
# Базовая настройка UFW
##
setup_basic_firewall() {
    echo -e "\n$(ColorCyan '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━')"
    echo -e "$(ColorBlue '🔥 Базовая настройка UFW файервола')"
    echo -e "$(ColorCyan '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━')\n"
    
    echo -e "$(ColorYellow '⚠️  Включаю UFW и разрешаю OpenSSH...')"
    ufw --force enable && ufw allow OpenSSH
    
    if [ $? -eq 0 ]; then
        echo -e "$(ColorGreen '✓ UFW успешно включен и OpenSSH разрешен!')"
    else
        echo -e "$(ColorRed '❌ Ошибка при настройке UFW')"
        exit 1
    fi
}

##
# Настройка портов XRAY
##
setup_xray_ports() {
    echo -e "\n$(ColorCyan '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━')"
    echo -e "$(ColorBlue '🚀 Настройка портов для XRAY')"
    echo -e "$(ColorCyan '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━')\n"
    
    echo -e "$(ColorYellow '→ Открываю порт 443/tcp...')"
    ufw allow 443/tcp
    
    echo -e "$(ColorYellow '→ Открываю порт 23/tcp...')"
    ufw allow 23/tcp
    
    echo -e "$(ColorGreen '✓ Порты XRAY настроены!')"
}

##
# Настройка портов OpenVPN
##
setup_openvpn_ports() {
    echo -e "\n$(ColorCyan '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━')"
    echo -e "$(ColorBlue '🔐 Настройка портов для OpenVPN')"
    echo -e "$(ColorCyan '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━')\n"
    
    echo -e "$(ColorYellow '→ Открываю порт 1194/udp...')"
    ufw allow 1194/udp
    
    echo -e "$(ColorGreen '✓ Порты OpenVPN настроены!')"
}

##
# Блокировка ICMP
##
block_icmp() {
    echo -e "\n$(ColorCyan '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━')"
    echo -e "$(ColorBlue '🛡️  Блокировка ICMP запросов (защита от пинга)')"
    echo -e "$(ColorCyan '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━')\n"
    
    # Создаем бэкап
    backup_config
    
    echo -e "$(ColorYellow '→ Модифицирую /etc/ufw/before.rules...')"
    
    # Добавляем правило source-quench и изменяем существующие на DROP
    sed -i '/# ok icmp codes for INPUT/,/# ok icmp code for FORWARD/ {
        /^-A ufw-before-input -p icmp --icmp-type destination-unreachable/s/ACCEPT/DROP/
        /^-A ufw-before-input -p icmp --icmp-type time-exceeded/s/ACCEPT/DROP/
        /^-A ufw-before-input -p icmp --icmp-type parameter-problem/s/ACCEPT/DROP/
        /^-A ufw-before-input -p icmp --icmp-type echo-request/s/ACCEPT/DROP/
    }' /etc/ufw/before.rules
    
    # Добавляем правило source-quench если его нет
    if ! grep -q "source-quench.*DROP" /etc/ufw/before.rules; then
        sed -i '/# ok icmp codes for INPUT/a -A ufw-before-input -p icmp --icmp-type source-quench -j DROP' /etc/ufw/before.rules
    fi
    
    echo -e "$(ColorYellow '→ Перезагружаю UFW для применения изменений...')"
    ufw disable && ufw --force enable
    
    echo -e "$(ColorGreen '✓ ICMP запросы заблокированы! Сервер не отвечает на пинг.')"
}

##
# Добавление пользовательского порта
##
add_custom_port() {
    echo -e "\n$(ColorYellow 'Введите порт для открытия (например: 8080):')"
    read -r port
    
    echo -e "$(ColorYellow 'Выберите протокол:')"
    echo -e "1) TCP"
    echo -e "2) UDP"
    echo -e "3) Оба"
    read -r proto_choice
    
    case $proto_choice in
        1)
            ufw allow "$port/tcp"
            echo -e "$(ColorGreen "✓ Порт $port/tcp открыт!")"
            ;;
        2)
            ufw allow "$port/udp"
            echo -e "$(ColorGreen "✓ Порт $port/udp открыт!")"
            ;;
        3)
            ufw allow "$port"
            echo -e "$(ColorGreen "✓ Порт $port (TCP и UDP) открыт!")"
            ;;
        *)
            echo -e "$(ColorRed '❌ Неверный выбор!')"
            ;;
    esac
}

##
# Показать статус UFW
##
show_status() {
    echo -e "\n$(ColorCyan '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━')"
    echo -e "$(ColorBlue '📊 Статус UFW файервола')"
    echo -e "$(ColorCyan '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━')\n"
    ufw status verbose
}

##
# Полная автоматическая настройка
##
full_auto_setup() {
    echo -e "\n$(ColorCyan '╔════════════════════════════════════════════╗')"
    echo -e "$(ColorCyan '║') $(ColorGreen '  🚀 ПОЛНАЯ АВТОМАТИЧЕСКАЯ НАСТРОЙКА  ') $(ColorCyan '║')"
    echo -e "$(ColorCyan '╚════════════════════════════════════════════╝')\n"
    
    setup_basic_firewall
    setup_xray_ports
    
    echo -e "\n$(ColorYellow 'Установлен ли у вас OpenVPN? (y/n):')"
    read -r has_openvpn
    
    if [[ $has_openvpn == "y" || $has_openvpn == "Y" ]]; then
        setup_openvpn_ports
    fi
    
    block_icmp
    
    echo -e "\n$(ColorCyan '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━')"
    echo -e "$(ColorGreen '✅ ПОЛНАЯ НАСТРОЙКА ЗАВЕРШЕНА!')"
    echo -e "$(ColorCyan '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━')\n"
    
    show_status
}

##
# Восстановление из бэкапа
##
restore_backup() {
    echo -e "\n$(ColorYellow 'Доступные бэкапы:')"
    ls -lh /etc/ufw/before.rules.backup_* 2>/dev/null || echo -e "$(ColorRed 'Бэкапов не найдено!')"
    
    echo -e "\n$(ColorYellow 'Введите полный путь к файлу бэкапа для восстановления:')"
    read -r backup_path
    
    if [ -f "$backup_path" ]; then
        cp "$backup_path" /etc/ufw/before.rules
        ufw disable && ufw --force enable
        echo -e "$(ColorGreen '✓ Конфигурация восстановлена из бэкапа!')"
    else
        echo -e "$(ColorRed '❌ Файл не найден!')"
    fi
}

##
# Главное меню
##
show_menu() {
    clear
    echo -e "$(ColorCyan '╔══════════════════════════════════════════════════╗')"
    echo -e "$(ColorCyan '║')  $(ColorBlue '🔥 UFW FIREWALL - ЗАЩИТА VPN ОТ ОБНАРУЖЕНИЯ') $(ColorCyan '║')"
    echo -e "$(ColorCyan '╚══════════════════════════════════════════════════╝')\n"
    
    echo -e "$(ColorGreen '1)') Полная автоматическая настройка 🚀"
    echo -e "$(ColorGreen '2)') Базовая настройка UFW"
    echo -e "$(ColorGreen '3)') Настроить порты XRAY"
    echo -e "$(ColorGreen '4)') Настроить порты OpenVPN"
    echo -e "$(ColorGreen '5)') Заблокировать ICMP (защита от пинга) 🛡️"
    echo -e "$(ColorGreen '6)') Добавить пользовательский порт"
    echo -e "$(ColorGreen '7)') Показать статус UFW 📊"
    echo -e "$(ColorGreen '8)') Восстановить из бэкапа"
    echo -e "$(ColorRed '9)') Выход ❌\n"
    
    echo -ne "$(ColorYellow 'Выберите опцию [1-9]: ')"
}

##
# Основной цикл
##
main() {
    check_root
    
    while true; do
        show_menu
        read -r choice
        
        case $choice in
            1)
                full_auto_setup
                ;;
            2)
                setup_basic_firewall
                ;;
            3)
                setup_xray_ports
                ;;
            4)
                setup_openvpn_ports
                ;;
            5)
                block_icmp
                ;;
            6)
                add_custom_port
                ;;
            7)
                show_status
                ;;
            8)
                restore_backup
                ;;
            9)
                echo -e "\n$(ColorGreen '👋 До свидания!')\n"
                exit 0
                ;;
            *)
                echo -e "\n$(ColorRed '❌ Неверный выбор! Попробуйте снова.')"
                ;;
        esac
        
        echo -e "\n$(ColorYellow 'Нажмите Enter для продолжения...')"
        read -r
    done
}

# Запуск скрипта
main
