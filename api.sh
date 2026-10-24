#!/system/bin/sh
# Backend cho WebUI:  sh api.sh <action> [args]
MODDIR="${0%/*}"
. "$MODDIR/common.sh" || exit 1
init_config

valid_id() { case "$1" in ''|*[!A-Za-z0-9_.-]*) return 1 ;; *) return 0 ;; esac; }

case "$1" in
    get)
        echo "threshold=$(get_threshold)"
        echo "recovery=$(get_recovery)"
        echo "lang=$(get_lang)"
        echo "count=$(get_count)"
        echo "last_trigger=$(kv_get "$STATE" last_trigger none)"
        echo "current_log=boot-$(num_or "$(kv_get "$STATE" log_idx 1)" 1).log"
        ;;
    set)
        case "$2" in
            threshold)
                case "$3" in 1|2|3|4|5) kv_set "$CONF" threshold "$3" ;; *) echo "ERR: threshold 1-5"; exit 1 ;; esac ;;
            recovery)
                case "$3" in 0|1) kv_set "$CONF" recovery "$3" ;; *) echo "ERR: recovery 0/1"; exit 1 ;; esac ;;
            lang)
                case "$3" in vi|en) kv_set "$CONF" lang "$3" ;; *) echo "ERR: lang vi/en"; exit 1 ;; esac ;;
            *) echo "ERR: unknown key"; exit 1 ;;
        esac
        update_desc "$MODDIR/module.prop"
        echo OK
        ;;
    modules)
        # id|name|version|enabled|whitelisted
        for d in "$MODS_DIR"/*/; do
            [ -d "$d" ] || continue
            id=$(basename "$d")
            [ "$id" = "$SELF_ID" ] && continue
            name=$(kv_get "$d/module.prop" name "$id" | tr -d '|')
            ver=$(kv_get "$d/module.prop" version "?" | tr -d '|')
            [ -f "$d/disable" ] && en=0 || en=1
            in_whitelist "$id" && wl=1 || wl=0
            echo "$id|$name|$ver|$en|$wl"
        done
        ;;
    setwl)
        list="$2"
        [ "$list" = "-" ] && list=""
        case "$list" in *[!A-Za-z0-9_.,-]*) echo "ERR: bad list"; exit 1 ;; esac
        kv_set "$CONF" whitelist "$list"
        echo OK
        ;;
    enable)
        valid_id "$2" || { echo "ERR: bad id"; exit 1; }
        rm -f "$MODS_DIR/$2/disable"
        if [ -f "$DISABLED_LIST" ]; then
            grep -vx "$2" "$DISABLED_LIST" > "$DISABLED_LIST.tmp"
            mv -f "$DISABLED_LIST.tmp" "$DISABLED_LIST"
        fi
        log "Bật lại module: $2"
        echo OK
        ;;
    restore)
        n=0
        if [ -f "$DISABLED_LIST" ]; then
            while read -r id; do
                valid_id "$id" || continue
                if [ -f "$MODS_DIR/$id/disable" ]; then
                    rm -f "$MODS_DIR/$id/disable"
                    n=$((n + 1))
                fi
            done < "$DISABLED_LIST"
            : > "$DISABLED_LIST"
        fi
        log "Khôi phục $n module bị tắt do bootloop"
        echo "$n"
        ;;
    reset)
        set_count 0
        echo OK
        ;;
    all)
        # Gộp mọi dữ liệu cho WebUI vào 1 lần gọi (đỡ phải mở nhiều phiên root)
        for sec in get modules history logs log; do
            echo "@@$sec"
            sh "$MODDIR/api.sh" "$sec"
        done
        ;;
    logs)
        # tên|kích thước|thời gian sửa (epoch), mới nhất trước
        ls -t "$LOG_DIR" 2>/dev/null | while read -r f; do
            case "$f" in boot-[0-9]*.log) ;; *) continue ;; esac
            echo "$f|$(wc -c < "$LOG_DIR/$f")|$(stat -c %Y "$LOG_DIR/$f" 2>/dev/null)"
        done
        ;;
    log)
        f="${2:-$(basename "$(cur_log_file)")}"
        case "$f" in boot-[0-9]|boot-10) f="$f.log" ;; esac
        case "$f" in boot-[0-9].log|boot-10.log) tail -n 300 "$LOG_DIR/$f" 2>/dev/null ;; *) echo "ERR: bad log name"; exit 1 ;; esac
        ;;
    history)
        tail -n 50 "$EVENTS" 2>/dev/null
        ;;
    clearhistory)
        : > "$EVENTS"
        echo OK
        ;;
    *)
        echo "ERR: unknown action"
        exit 1
        ;;
esac
