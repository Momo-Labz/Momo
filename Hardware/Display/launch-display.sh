#!/bin/sh
set -eu

display_url_file="${BARBOY_URL_FILE:-/home/barboy/.config/barboy/display-url}"
if [ ! -s "$display_url_file" ]; then
  echo "Put the paired MOMO display URL in $display_url_file" >&2
  exit 1
fi

display_url="$(sed -n '1p' "$display_url_file")"
exec chromium --kiosk --noerrdialogs --disable-infobars --disable-session-crashed-bubble --app="$display_url"
