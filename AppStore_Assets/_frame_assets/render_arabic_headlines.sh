#!/bin/bash
set -e
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
OUT_DIR="$(dirname "$0")/arabic_headlines"
declare -a TEXTS=("تتبع ساعاتك" "شاهد أسبوعك" "إدارة الورديات")
for i in 1 2 3; do
  idx=$((i-1))
  text="${TEXTS[$idx]}"
  html="/tmp/arabic_headline_$i.html"
  cat > "$html" <<EOF
<!DOCTYPE html>
<html dir="rtl"><head><meta charset="utf-8"><style>
html,body{margin:0;padding:0;background:transparent;}
body{width:1320px;height:260px;display:flex;align-items:center;justify-content:center;}
div{font-family:"Al Bayan","Geeza Pro","Arial Hebrew",sans-serif;font-weight:bold;font-size:92px;color:#FFFFFF;white-space:nowrap;}
</style></head><body><div>$text</div></body></html>
EOF
  "$CHROME" --headless --disable-gpu --hide-scrollbars --default-background-color=00000000 \
    --window-size=1320,260 --screenshot="$OUT_DIR/h$i.png" "file://$html" 2>/dev/null
  rm "$html"
done
