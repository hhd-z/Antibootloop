#!/system/bin/sh
MODDIR="${0%/*}"
. "$MODDIR/common.sh" || exit 1

init_config
rotate_log

threshold=$(get_threshold)
count=$(get_count)
log "Boot mới | số lần boot lỗi liên tiếp: $count / ngưỡng: $threshold"

if [ "$count" -ge "$threshold" ]; then
    log "!!! Phát hiện bootloop -> tắt toàn bộ module"
    disable_all_modules
    if [ "$(get_recovery)" = "1" ]; then rec_txt="vào recovery"; else rec_txt="reboot thường"; fi
    record_event trigger "Sau $count lần boot lỗi (ngưỡng $threshold): đã tắt ${DISABLED_TOTAL:-0} module, $rec_txt"
    set_count 0
    kv_set "$STATE" last_trigger "$(date -u '+%F %T')"
    if [ "$(get_recovery)" = "1" ]; then
        log "Reboot vào recovery"
        do_reboot recovery
    else
        log "Reboot bình thường"
        do_reboot
    fi
    exit 0
fi

# Ghi nhận boot này là "chưa chắc thành công"; service.sh sẽ reset về 0 khi boot xong
set_count $((count + 1))
