#!/bin/sh
# Build-фаза «Set Local API host».
# В Debug-сборке (схема «Local») подставляет адрес локального бэкенда
#   http://<IP-этой-машины-в-Wi-Fi>:8001/api/v1
# в ключ API_BASE_URL уже собранного Info.plist. В Release (схема «Prod»)
# ничего не делает — остаётся прод-адрес, зашитый в Info.plist.
#
# IP берётся автоматически (ipconfig getifaddr en0 → en1), руками ничего не правишь.
set -e

if [ "${CONFIGURATION}" != "Debug" ]; then
  echo "note: конфигурация ${CONFIGURATION} — оставляю API_BASE_URL из Info.plist (прод)"
  exit 0
fi

# Порт локального API чата (docker-compose.yml: API_PORT=8001).
LOCAL_API_PORT="${LOCAL_API_PORT:-8001}"

# IP машины в локальной сети: сначала Wi-Fi (en0), затем запасной интерфейс (en1).
IP="$(ipconfig getifaddr en0 2>/dev/null || true)"
[ -z "$IP" ] && IP="$(ipconfig getifaddr en1 2>/dev/null || true)"

if [ -z "$IP" ]; then
  echo "warning: не удалось определить IP (en0/en1). Оставляю адрес из Info.plist."
  exit 0
fi

URL="http://${IP}:${LOCAL_API_PORT}/api/v1"
PLIST="${TARGET_BUILD_DIR}/${INFOPLIST_PATH}"

/usr/libexec/PlistBuddy -c "Set :API_BASE_URL ${URL}" "${PLIST}" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Add :API_BASE_URL string ${URL}" "${PLIST}"

echo "note: API_BASE_URL -> ${URL}"
