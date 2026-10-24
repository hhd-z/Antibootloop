# Anti Bootloop - installer (Magisk / KernelSU / APatch)
. "$MODPATH/common.sh"

# Trả về: 0 = Vol+, 1 = Vol-, 2 = hết thời gian chờ
chooseport() {
  local delay="${1:-30}" line
  line=$(timeout -s 2 "$delay" /system/bin/getevent -lq 2>/dev/null | grep -m 1 -E "KEY_VOLUMEUP.*DOWN|KEY_VOLUMEDOWN.*DOWN")
  case "$line" in
    *KEY_VOLUMEUP*)   sleep 0.3; return 0 ;;
    *KEY_VOLUMEDOWN*) sleep 0.3; return 1 ;;
  esac
  return 2
}

ui_print ""
ui_print "  ================================"
ui_print "          ANTI BOOTLOOP"
ui_print "  ================================"
ui_print ""
ui_print "◆ (1/2) Số lần boot lỗi liên tiếp để"
ui_print "        tính là bootloop? (1 - 5)"
ui_print ""
ui_print "  [Vol- = Chuyển số tiếp theo]"
ui_print "  [Vol+ = Chọn số đang hiện]"
ui_print ""

threshold=1
while true; do
  ui_print "  ► Hiện tại: $threshold"
  chooseport 30
  key=$?
  if [ "$key" -eq 0 ]; then
    break
  elif [ "$key" -eq 1 ]; then
    threshold=$((threshold % 5 + 1))
  else
    threshold=3
    ui_print "  ! Không nhận được phím, dùng mặc định: 3"
    break
  fi
done
ui_print "  ✔ Ngưỡng bootloop: $threshold lần"

ui_print ""
ui_print "◆ (2/2) Khi bootloop, có reboot vào"
ui_print "        recovery không?"
ui_print ""
ui_print "  [Vol+ = CÓ  |  Vol- = KHÔNG]"
chooseport 30
key=$?
if [ "$key" -eq 1 ]; then
  recovery=0
  ui_print "  ✘ Không vào recovery (chỉ reboot thường)"
else
  recovery=1
  [ "$key" -eq 2 ] && ui_print "  ! Không nhận được phím, dùng mặc định: CÓ"
  ui_print "  ✔ Sẽ reboot vào recovery"
fi

ui_print ""
ui_print "- Đang ghi cấu hình..."
init_config
kv_set "$CONF" threshold "$threshold"
kv_set "$CONF" recovery "$recovery"
kv_set "$STATE" count 0
update_desc "$MODPATH/module.prop"

ui_print ""
ui_print "  ================================"
ui_print "   Ngưỡng bootloop : $threshold lần"
ui_print "   Vào recovery    : $([ "$recovery" = "1" ] && echo CÓ || echo KHÔNG)"
ui_print "   Chỉnh lại sau   : WebUI / nút Action"
ui_print "  ================================"
ui_print "  ⚡ Reboot để kích hoạt."
ui_print ""

set_permissions() {
  set_perm_recursive "$MODPATH" 0 0 0755 0644
  for f in common.sh post-fs-data.sh service.sh api.sh action.sh uninstall.sh webroot/cgi-bin/api; do
    [ -f "$MODPATH/$f" ] && set_perm "$MODPATH/$f" 0 0 0755
  done
}
