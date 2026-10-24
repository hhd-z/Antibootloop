#!/system/bin/sh
# Anti Bootloop - hàm dùng chung

SELF_ID="anti_bootloop"
: "${MODS_DIR:=/data/adb/modules}"
: "${DATA_DIR:=/data/adb/anti_bootloop}"
CONF="$DATA_DIR/config.prop"
STATE="$DATA_DIR/state.prop"
DISABLED_LIST="$DATA_DIR/disabled.list"
LOG_DIR="$DATA_DIR/logs"
EVENTS="$DATA_DIR/events.log"
MAX_LOGS=10

cur_log_file() {
    i=$(num_or "$(kv_get "$STATE" log_idx 1)" 1)
    printf '%s/boot-%s.log' "$LOG_DIR" "$i"
}

log() {
    mkdir -p "$LOG_DIR"
    echo "[$(date -u '+%T')] $*" >> "$(cur_log_file)"
}

# Bắt đầu file log mới cho lần boot này (xoay vòng $MAX_LOGS file)
rotate_log() {
    mkdir -p "$LOG_DIR"
    i=$(num_or "$(kv_get "$STATE" log_idx 0)" 0)
    i=$(( i % MAX_LOGS + 1 ))
    kv_set "$STATE" log_idx "$i"
    : > "$LOG_DIR/boot-$i.log"
    log "===== BOOT MỚI ($(date -u '+%F %T')) ====="
}

# Ghi nhận sự kiện bootloop: record_event <loại> <chi tiết>
#   loại: trigger | timeout | systemui
record_event() {
    mkdir -p "$DATA_DIR"
    echo "$(date -u '+%F %T')|$1|$2" >> "$EVENTS"
    if [ "$(wc -l < "$EVENTS" 2>/dev/null)" -gt 100 ]; then
        tail -n 60 "$EVENTS" > "$EVENTS.tmp" && mv -f "$EVENTS.tmp" "$EVENTS"
    fi
}

# kv_get <file> <key> <default>
kv_get() {
    v=$(grep "^$2=" "$1" 2>/dev/null | head -n 1 | cut -d= -f2- | tr -d '\r')
    if [ -n "$v" ]; then printf '%s' "$v"; else printf '%s' "$3"; fi
}

# kv_set <file> <key> <value>   (value không được chứa ~ hoặc &)
kv_set() {
    mkdir -p "$(dirname "$1")"
    [ -f "$1" ] || : > "$1"
    if grep -q "^$2=" "$1"; then
        sed -i "s~^$2=.*~$2=$3~" "$1"
    else
        echo "$2=$3" >> "$1"
    fi
}

num_or() { # num_or <value> <default>
    case "$1" in ''|*[!0-9]*) printf '%s' "$2" ;; *) printf '%s' "$1" ;; esac
}

init_config() {
    mkdir -p "$DATA_DIR"
    [ -f "$CONF" ] || {
        kv_set "$CONF" threshold 3
        kv_set "$CONF" recovery 1
        kv_set "$CONF" whitelist ""
        kv_set "$CONF" lang vi
        kv_set "$CONF" boot_timeout 180
        kv_set "$CONF" stable_time 30
    }
    [ -f "$STATE" ] || {
        kv_set "$STATE" count 0
        kv_set "$STATE" last_trigger none
        kv_set "$STATE" log_idx 0
    }
}

get_threshold() {
    t=$(kv_get "$CONF" threshold 3)
    case "$t" in 1|2|3|4|5) printf '%s' "$t" ;; *) printf '3' ;; esac
}

get_recovery() {
    r=$(kv_get "$CONF" recovery 1)
    [ "$r" = "0" ] && printf '0' || printf '1'
}

get_lang() {
    l=$(kv_get "$CONF" lang vi)
    [ "$l" = "en" ] && printf 'en' || printf 'vi'
}

get_count() { num_or "$(kv_get "$STATE" count 0)" 0; }
set_count() { kv_set "$STATE" count "$1"; }

# Module nằm trong danh sách "không bị tắt"
in_whitelist() {
    case ",$(kv_get "$CONF" whitelist '')," in
        *",$1,"*) return 0 ;;
    esac
    return 1
}

# Tắt tất cả module (trừ chính nó và module trong whitelist)
disable_all_modules() {
    total=0
    for d in "$MODS_DIR"/*/; do
        [ -d "$d" ] || continue
        id=$(basename "$d")
        [ "$id" = "$SELF_ID" ] && continue
        [ -f "$d/remove" ] && continue
        if in_whitelist "$id"; then
            log "Giữ nguyên (whitelist): $id"
            continue
        fi
        if [ ! -f "$d/disable" ]; then
            touch "$d/disable"
            grep -qx "$id" "$DISABLED_LIST" 2>/dev/null || echo "$id" >> "$DISABLED_LIST"
            log "Đã tắt module: $id"
            total=$((total + 1))
        fi
    done
    DISABLED_TOTAL=$total
    log "Tổng số module đã tắt: $total"
}

do_reboot() { # do_reboot [recovery]
    sync
    if [ "$1" = "recovery" ]; then
        reboot recovery || setprop sys.powerctl reboot,recovery
    else
        reboot || setprop sys.powerctl reboot
    fi
}

# Cập nhật mô tả hiển thị trong app root
update_desc() { # update_desc <module.prop>
    [ -f "$1" ] || return 0
    if [ "$(get_lang)" = "en" ]; then
        if [ "$(get_recovery)" = "1" ]; then rec="On"; else rec="Off"; fi
        d="🛡️ Anti Bootloop | Threshold: $(get_threshold) boots | Reboot to recovery: $rec | Auto-disables modules on bootloop."
    else
        if [ "$(get_recovery)" = "1" ]; then rec="Bật"; else rec="Tắt"; fi
        d="🛡️ Anti Bootloop | Ngưỡng: $(get_threshold) lần | Reboot recovery: $rec | Tự tắt module khi bootloop."
    fi
    sed -i "s~^description=.*~description=$d~" "$1"
}

find_busybox() {
    for c in /data/adb/ksu/bin/busybox /data/adb/magisk/busybox /data/adb/ap/bin/busybox /system/bin/busybox; do
        if [ -x "$c" ] && "$c" true >/dev/null 2>&1; then
            echo "$c"; return 0
        fi
    done
    command -v busybox 2>/dev/null
}
