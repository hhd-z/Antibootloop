#!/system/bin/sh
# Nút Action: mở WebUI (cho root manager không có WebUI sẵn như Magisk)
MODDIR="${0%/*}"
. "$MODDIR/common.sh" || exit 1
init_config

echo ""
echo "=============================="
echo "         ANTI BOOTLOOP"
echo "=============================="
echo "- Ngưỡng bootloop : $(get_threshold) lần"
echo "- Vào recovery    : $([ "$(get_recovery)" = "1" ] && echo CÓ || echo KHÔNG)"
echo "- Boot lỗi hiện tại: $(get_count)"
echo "- Lần kích hoạt cuối: $(kv_get "$STATE" last_trigger none) (UTC)"
echo ""

BB=$(find_busybox)
[ -z "$BB" ] && { echo "! Không tìm thấy busybox, hãy mở WebUI từ app root manager."; exit 1; }

WEBUI="$MODDIR/webui"
SESSION=600

# Tắt phiên cũ
if [ -f "$WEBUI/port" ]; then
    "$BB" pkill -f "httpd -p 127.0.0.1:$(cat "$WEBUI/port")" >/dev/null 2>&1
fi
rm -rf "$WEBUI"; mkdir -p "$WEBUI"

# Chọn port ngẫu nhiên còn trống
for i in 1 2 3 4 5; do
    r=$(od -An -N2 -tu2 /dev/urandom | tr -d ' ')
    PORT=$((20000 + r % 20000))
    hex=$(printf '%04X' "$PORT")
    grep -q ":$hex " /proc/net/tcp /proc/net/tcp6 2>/dev/null || break
done

TOKEN=$(cat /proc/sys/kernel/random/uuid 2>/dev/null)
[ -z "$TOKEN" ] && TOKEN=$(od -An -N16 -tx1 /dev/urandom | tr -d ' \n')
echo "$TOKEN" > "$WEBUI/token"; chmod 600 "$WEBUI/token"
echo "$PORT" > "$WEBUI/port"
chmod 755 "$MODDIR/webroot/cgi-bin/api" "$MODDIR/api.sh"

export PATH="$(dirname "$BB"):$PATH"
"$BB" httpd -p "127.0.0.1:$PORT" -h "$MODDIR/webroot"
sleep 1
if ! "$BB" pgrep -f "httpd -p 127.0.0.1:$PORT" >/dev/null 2>&1; then
    echo "! Không khởi động được server."; rm -rf "$WEBUI"; exit 1
fi

# Tự tắt server sau $SESSION giây
nohup sh -c "sleep $SESSION; '$BB' pkill -f 'httpd -p 127.0.0.1:$PORT'; rm -rf '$WEBUI'" >/dev/null 2>&1 &

echo "- WebUI: http://127.0.0.1:$PORT (tự tắt sau $((SESSION/60)) phút)"
am start -a android.intent.action.VIEW -d "http://127.0.0.1:$PORT/#$TOKEN" >/dev/null 2>&1
