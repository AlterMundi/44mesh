#!/bin/sh
set -eu

ZT_TOKEN_FILE="/var/lib/zerotier-one/authtoken.secret"
ENV_FILE="/opt/altermundi/zerotier-ui/src/.env"

if [ -z "${ZT_TOKEN:-}" ]; then
    if [ -f "$ZT_TOKEN_FILE" ]; then
        ZT_TOKEN="$(cat "$ZT_TOKEN_FILE")"
    else
        echo "ERROR: ZT_TOKEN not set and $ZT_TOKEN_FILE not found"
        exit 1
    fi
fi

: "${ZT_ADDR:=127.0.0.1:9993}"
: "${ZTNCUI_HTTP_PORT:=3180}"
: "${ZTNCUI_HTTPS_PORT:=}"
: "${ZTNCUI_HTTP_ALL_INTERFACES:=}"
: "${ZTNCUI_HTTPS_HOST:=}"
: "${ZTNCUI_PASSWD:=password}"
: "${NODE_ENV:=production}"
: "${SESSION_SECRET:=}"

# Warn if SESSION_SECRET is not configured (sessions won't survive restarts)
if [ -z "$SESSION_SECRET" ]; then
    echo "WARNING: SESSION_SECRET not set — sessions will be lost on container restart"
fi

# Fix volume permissions so ztncui can write to etc/storage
ETC_DIR="/opt/altermundi/zerotier-ui/src/etc"
mkdir -p "${ETC_DIR}/storage"
chown -R ztncui:ztgrp "${ETC_DIR}"

{
    echo "ZT_TOKEN=$ZT_TOKEN"
    echo "ZT_ADDR=$ZT_ADDR"
    echo "NODE_ENV=$NODE_ENV"
    echo "HTTP_PORT=$ZTNCUI_HTTP_PORT"
    [ -n "$ZTNCUI_HTTPS_PORT" ] && echo "HTTPS_PORT=$ZTNCUI_HTTPS_PORT"
    echo "HTTP_ALL_INTERFACES=$ZTNCUI_HTTP_ALL_INTERFACES"
    [ -n "$ZTNCUI_HTTPS_HOST" ] && echo "HTTPS_HOST=$ZTNCUI_HTTPS_HOST"
    echo "PASSWD=$ZTNCUI_PASSWD"
    [ -n "$SESSION_SECRET" ] && echo "SESSION_SECRET=$SESSION_SECRET"
} > "$ENV_FILE"

chmod 600 "$ENV_FILE"
chown ztncui "$ENV_FILE"

cd /opt/altermundi/zerotier-ui/src
exec gosu ztncui npm start
