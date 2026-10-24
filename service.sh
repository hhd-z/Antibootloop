#!/system/bin/sh
MODDIR="${0%/*}"
. "$MODDIR/common.sh" || exit 1

init_config

real_count=$(get_count)
boot_timeout=$(num_or "$(kv_get "$CONF" boot_timeout 180)" 180)
stable_time=$(num_or "$(kv_get "$CONF" stable_time 30)" 30)

# 1) Chờ boot hoàn tất. Treo quá lâu -> reboot để được tính là 1 lần lỗi
start=$(date +%s)
while [ "$(getprop sys.boot_completed)" != "1" ]; do
    now=$(date +%s)
    if [ $((now - start)) -ge "$boot_timeout" ]; then
        log "Boot không hoàn tất sau ${boot_timeout}s -> reboot (count=$real_count)"
        record_event timeout "Boot treo quá ${boot_timeout}s, tự reboot (boot lỗi: $real_count/$(get_threshold))"
        do_reboot
        exit 0
    fi
    sleep 2
done

# Boot xong: reset ngay để reboot thủ công không bị tính là lỗi
set_count 0
log "Boot hoàn tất sau $(( $(date +%s) - start ))s, đã reset bộ đếm"

# 2) Theo dõi SystemUI một lúc để bắt kiểu lỗi "vào được hệ thống rồi crash"
miss=0
crashes=0
last_pid=""
end=$(( $(date +%s) + stable_time ))
while [ "$(date +%s)" -lt "$end" ]; do
    pid=$(pidof com.android.systemui 2>/dev/null | cut -d' ' -f1)
    if [ -z "$pid" ]; then
        miss=$((miss + 1))
    else
        miss=0
        [ -n "$last_pid" ] && [ "$pid" != "$last_pid" ] && crashes=$((crashes + 1))
        last_pid="$pid"
    fi
    if [ "$miss" -ge 3 ] || [ "$crashes" -ge 3 ]; then
        log "SystemUI lỗi (mất: $miss, crash: $crashes) -> reboot, khôi phục count=$real_count"
        set_count "$real_count"
        record_event systemui "SystemUI lỗi sau khi boot (mất: $miss, crash: $crashes), tự reboot (boot lỗi: $real_count/$(get_threshold))"
        do_reboot
        exit 0
    fi
    sleep 3
done

log "Hệ thống ổn định."
