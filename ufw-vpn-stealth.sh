#!/usr/bin/env bash
set -Eeuo pipefail

# ============ Цвета ============
GREEN='\e[32m'; BLUE='\e[34m'; RED='\e[31m'; YELLOW='\e[33m'; CYAN='\e[36m'; CLEAR='\e[0m'
say() { echo -e "$1"; }
ok(){ say "${GREEN}✓${CLEAR} $1"; }
info(){ say "${BLUE}ℹ${CLEAR} $1"; }
warn(){ say "${YELLOW}⚠${CLEAR} $1"; }
err(){ say "${RED}✖${CLEAR} $1"; }

# ============ Проверки ============
need_root() {
  if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
    err "Запустите с правами root (sudo)."
    exit 1
  fi
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || { err "Не найдено: $1"; exit 1; }
}

detect_os() {
  if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    OS_ID=${ID:-unknown}
  else
    OS_ID="unknown"
  fi
}

ensure_ufw() {
  if ! command -v ufw >/dev/null 2>&1; then
    warn "UFW не найден. Установить? (y/n)"
    read -r a
    if [[ ${a,,} == "y" ]]; then
      detect_os
      case "$OS_ID" in
        ubuntu|debian) apt-get update -y && apt-get install -y ufw ;;
        *) err "Автоустановка не поддерживается для вашей системы. Установите UFW вручную."; exit 1 ;;
      esac
    else
      err "UFW не установлен — выход."
      exit 1
    fi
  fi
}

# ============ Бэкап ============
backup_before_rules() {
  local src="/etc/ufw/before.rules"
  local dst="/etc/ufw/before.rules.backup_$(date +%Y%m%d_%H%M%S)"
  if [[ -f "$src" ]]; then
    cp "$src" "$dst"
    ok "Бэкап создан: $dst"
  else
    warn "Файл $src не найден. Возможно UFW ещё не инициализирован — будет создан позже."
  fi
}

# ============ Действия ============
setup_basic_firewall() {
  say "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${CLEAR}"
  info "Базовая настройка UFW"
  say "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${CLEAR}"

  ufw --force enable
  ufw allow OpenSSH
  ok "UFW включён, OpenSSH разрешён."
}

setup_xray_ports() {
  say "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${CLEAR}"
  info "Настройка портов XRAY"
  say "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${CLEAR}"

  ufw allow 443/tcp
  ufw allow 23/tcp
  ok "Открыты 443/tcp и 23/tcp."
}

setup_openvpn_ports() {
  say "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${CLEAR}"
  info "Настройка портов OpenVPN"
  say "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${CLEAR}"

  ufw allow 1194/udp
  ok "Открыт 1194/udp."
}

block_icmp() {
  say "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${CLEAR}"
  info "Блокировка ICMP (пинг) в UFW"
  say "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${CLEAR}"

  backup_before_rules

  # Убедимся, что файл существует: если нет — активируем UFW (создаёт шаблоны) и создадим бэкап ещё раз.
  if [[ ! -f /etc/ufw/before.rules ]]; then
    ufw --force enable || true
    [[ -f /etc/ufw/before.rules ]] && backup_before_rules
  fi

  # Правки в блоке ICMP: меняем ACCEPT -> DROP, добавляем source-quench DROP.
  sed -i '/# ok icmp codes for INPUT/,/# ok icmp code for FORWARD/ {
    s/--icmp-type destination-unreachable.*ACCEPT/--icmp-type destination-unreachable -j DROP/
    s/--icmp-type time-exceeded.*ACCEPT/--icmp-type time-exceeded -j DROP/
    s/--icmp-type parameter-problem.*ACCEPT/--icmp-type parameter-problem -j DROP/
    s/--icmp-type echo-request.*ACCEPT/--icmp-type echo-request -j DROP/
  }' /etc/ufw/before.rules

  # Добавим строку source-quench DROP, если её нет
  if ! grep -qE '^-A ufw-before-input -p icmp --icmp-type source-quench -j DROP' /etc/ufw/before.rules; then
    sed -i '/# ok icmp codes for INPUT/a -A ufw-before-input -p icmp --icmp-type source-quench -j DROP' /etc/ufw/before.rules
  fi

  ufw disable >/dev/null 2>&1 || true
  ufw --force enable
  ok "ICMP блокирован. Сервер не отвечает на ping."
  warn "Помните: полная блокировка ICMP может повлиять на диагностику сети и PMTU."
}

add_custom_port() {
  read -rp "Введите порт (например 8080): " port
  say "Выберите протокол: 1) TCP  2) UDP  3) Оба"
  read -rp "[1-3]: " p
  case "$p" in
    1) ufw allow "${port}/tcp"; ok "Открыт ${port}/tcp";;
    2) ufw allow "${port}/udp"; ok "Открыт ${port}/udp";;
    3) ufw allow "${port}"; ok "Открыт ${port}/tcp и /udp";;
    *) err "Некорректный выбор";;
  esac
}

show_status() {
  say "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${CLEAR}"
  info "Статус UFW"
  say "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${CLEAR}"
  ufw status verbose
}

restore_backup() {
  say "Доступные бэкапы:"
  ls -1 /etc/ufw/before.rules.backup_* 2>/dev/null || say "— нет файлов"
  read -rp "Укажите путь к бэкапу для восстановления: " path
  if [[ -f "$path" ]]; then
    cp "$path" /etc/ufw/before.rules
    ufw disable >/dev/null 2>&1 || true
    ufw --force enable
    ok "Восстановлено из: $path"
  else
    err "Файл не найден."
  fi
}

full_auto() {
  setup_basic_firewall
  setup_xray_ports
  read -rp "Установлен OpenVPN? (y/n): " a
  if [[ ${a,,} == "y" ]]; then
    setup_openvpn_ports
  fi
  block_icmp
  show_status
}

# ============ Меню ============
menu() {
  clear
  say "${CYAN}╔══════════════════════════════════════════════════╗${CLEAR}"
  say "${CYAN}║${CLEAR}  ${BLUE}UFW FIREWALL • VPN STEALTH (ICMP BLOCK)${CLEAR}  ${CYAN}║${CLEAR}"
  say "${CYAN}╚══════════════════════════════════════════════════╝${CLEAR}"
  say "  1) Полная настройка"
  say "  2) Базовая настройка (enable UFW + OpenSSH)"
  say "  3) Порты XRAY (443/tcp, 23/tcp)"
  say "  4) Порты OpenVPN (1194/udp)"
  say "  5) Заблокировать ICMP"
  say "  6) Добавить пользовательский порт"
  say "  7) Показать статус UFW"
  say "  8) Восстановить бэкап /etc/ufw/before.rules"
  say "  9) Выход"
  read -rp "Выбор [1-9]: " c
  case "$c" in
    1) full_auto ;;
    2) setup_basic_firewall ;;
    3) setup_xray_ports ;;
    4) setup_openvpn_ports ;;
    5) block_icmp ;;
    6) add_custom_port ;;
    7) show_status ;;
    8) restore_backup ;;
    9) exit 0 ;;
    *) err "Некорректный выбор";;
  esac
  read -rp "Нажмите Enter для продолжения..." _
}

main() {
  need_root
  ensure_ufw
  while true; do menu; done
}

main "$@"
