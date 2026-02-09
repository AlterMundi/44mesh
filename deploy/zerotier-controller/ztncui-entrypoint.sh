#!/bin/sh
set -eu

ZT_TOKEN_FILE="/var/lib/zerotier-one/authtoken.secret"
ENV_FILE="/opt/key-networks/ztncui/.env"

if [ -z "${ZT_TOKEN:-}" ]; then
    if [ -f "$ZT_TOKEN_FILE" ]; then
        ZT_TOKEN="$(cat "$ZT_TOKEN_FILE")"
    else
        echo "ERROR: ZT_TOKEN not set and $ZT_TOKEN_FILE not found"
        exit 1
    fi
fi

: "${ZT_ADDR:=127.0.0.1:9993}"
: "${ZTNCUI_HTTP_PORT:=3000}"
: "${ZTNCUI_HTTPS_PORT:=3443}"
: "${ZTNCUI_HTTP_ALL_INTERFACES:=}"
: "${ZTNCUI_HTTPS_HOST:=}"
: "${ZTNCUI_PASSWD:=password}"
: "${NODE_ENV:=production}"

{
    echo "ZT_TOKEN=$ZT_TOKEN"
    echo "ZT_ADDR=$ZT_ADDR"
    echo "NODE_ENV=$NODE_ENV"
    echo "HTTP_PORT=$ZTNCUI_HTTP_PORT"
    echo "HTTPS_PORT=$ZTNCUI_HTTPS_PORT"
    echo "HTTP_ALL_INTERFACES=$ZTNCUI_HTTP_ALL_INTERFACES"
    echo "HTTPS_HOST=$ZTNCUI_HTTPS_HOST"
    echo "PASSWD=$ZTNCUI_PASSWD"
} > "$ENV_FILE"

chmod 600 "$ENV_FILE"

cd /opt/key-networks/ztncui
exec npm start
