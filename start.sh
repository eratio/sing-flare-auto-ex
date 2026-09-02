#!/bin/sh

set -eu


# ==================================================
# Paths
# ==================================================

DATA_DIR="/data"

RUNTIME_FILE="${DATA_DIR}/runtime.json"

CONFIG_TEMPLATE="/app/config.json.template"

CONFIG_FILE="/app/config.json"


# ==================================================
# Banner
# ==================================================

echo ""

echo "=================================================="
echo " Sing-Flare-Auto"
echo " ARM64 / AMD64"
echo "=================================================="

echo ""


# ==================================================
# Required variables
# ==================================================

if [ -z "${ARGO_TOKEN:-}" ]; then

    echo "[ERROR] ARGO_TOKEN is required"

    exit 1

fi


# ==================================================
# Create data directory
# ==================================================

mkdir -p "$DATA_DIR"


# ==================================================
# Validate UUID
# ==================================================

validate_uuid() {

    UUID_VALUE="$1"

    echo "$UUID_VALUE" \
        | grep -Eq \
        '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'

}


# ==================================================
# Load saved UUID
# ==================================================

SAVED_UUID=""

SAVED_WS_PATH=""


if [ -f "$RUNTIME_FILE" ]; then

    echo "[INFO] Loading runtime configuration"


    SAVED_UUID=$(jq -r \
        '.uuid // empty' \
        "$RUNTIME_FILE" \
        2>/dev/null \
        || true)


    SAVED_WS_PATH=$(jq -r \
        '.ws_path // empty' \
        "$RUNTIME_FILE" \
        2>/dev/null \
        || true)

fi


# ==================================================
# UUID
# ==================================================

if [ -n "${UUID:-}" ]; then

    FINAL_UUID="$UUID"

    echo "[INFO] Using UUID from environment"


elif [ -n "$SAVED_UUID" ]; then

    FINAL_UUID="$SAVED_UUID"

    echo "[INFO] Using saved UUID"


else

    echo "[INFO] Generating UUID"


    FINAL_UUID=$(

        cat \
            /proc/sys/kernel/random/uuid

    )

fi


# Validate UUID

if ! validate_uuid "$FINAL_UUID"; then

    echo "[ERROR] Invalid UUID"

    echo ""

    echo "UUID must look like:"

    echo "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"

    exit 1

fi


# ==================================================
# WebSocket Path
# ==================================================

if [ -n "${WS_PATH:-}" ]; then

    FINAL_WS_PATH="$WS_PATH"

    echo "[INFO] Using WS_PATH from environment"


elif [ -n "$SAVED_WS_PATH" ]; then

    FINAL_WS_PATH="$SAVED_WS_PATH"

    echo "[INFO] Using saved WebSocket path"


else

    echo "[INFO] Generating WebSocket path"


    RANDOM_PATH=$(

        tr -dc \
            'a-z0-9' \
            < /dev/urandom \
            | head -c 24

    )


    FINAL_WS_PATH="/${RANDOM_PATH}"

fi


# ==================================================
# Normalize WebSocket Path
# ==================================================

case "$FINAL_WS_PATH" in

    /*)

        ;;

    *)

        FINAL_WS_PATH="/${FINAL_WS_PATH}"

        ;;

esac


# ==================================================
# Validate WebSocket Path
# ==================================================

if [ "$FINAL_WS_PATH" = "/" ]; then

    echo "[ERROR] WS_PATH cannot be /"

    exit 1

fi


# ==================================================
# Save runtime configuration
# ==================================================

jq -n \
    --arg uuid "$FINAL_UUID" \
    --arg ws_path "$FINAL_WS_PATH" \
    '{
        uuid: $uuid,
        ws_path: $ws_path
    }' \
    > "$RUNTIME_FILE"


chmod 600 "$RUNTIME_FILE"


# ==================================================
# Export
# ==================================================

export UUID="$FINAL_UUID"

export WS_PATH="$FINAL_WS_PATH"


# ==================================================
# System information
# ==================================================

echo ""

echo "Architecture:"

uname -m


echo ""

echo "sing-box version:"

sing-box version


echo ""

echo "cloudflared version:"

cloudflared --version


echo ""


# ==================================================
# Generate configuration
# ==================================================

echo "[INFO] Generating sing-box configuration"


envsubst \
    < "$CONFIG_TEMPLATE" \
    > "$CONFIG_FILE"


# ==================================================
# Validate configuration
# ==================================================

echo "[INFO] Checking sing-box configuration"


sing-box check \
    -c "$CONFIG_FILE"


echo "[INFO] Configuration OK"


# ==================================================
# Start sing-box
# ==================================================

echo ""

echo "[INFO] Starting sing-box"


sing-box run \
    -c "$CONFIG_FILE" &


SING_BOX_PID=$!


sleep 2


if ! kill -0 \
    "$SING_BOX_PID" \
    2>/dev/null
then

    echo "[ERROR] sing-box failed to start"

    exit 1

fi


echo "[INFO] sing-box started"


# ==================================================
# Start cloudflared
# ==================================================

echo ""

echo "[INFO] Starting Cloudflare Tunnel"


cloudflared tunnel \
    --no-autoupdate \
    run \
    --token "$ARGO_TOKEN" &


CLOUDFLARED_PID=$!


sleep 3


if ! kill -0 \
    "$CLOUDFLARED_PID" \
    2>/dev/null
then

    echo "[ERROR] cloudflared failed to start"

    kill "$SING_BOX_PID" \
        2>/dev/null \
        || true

    exit 1

fi


echo "[INFO] Cloudflare Tunnel started"


# ==================================================
# Client Information
# ==================================================

echo ""

echo "=================================================="

echo " Client Configuration"

echo "=================================================="


echo ""

echo "UUID:"

echo "$FINAL_UUID"


echo ""

echo "WebSocket Path:"

echo "$FINAL_WS_PATH"


echo ""


if [ -n "${HOST:-}" ]; then

    echo "Host:"

    echo "$HOST"


    echo ""

    echo "VLESS URI:"


    ENCODED_PATH=$(

        printf '%s' \
            "$FINAL_WS_PATH" \
            | jq -sRr @uri

    )


    echo ""


    printf '%s\n' \
        "vless://${FINAL_UUID}@${HOST}:443?encryption=none&security=tls&sni=${HOST}&type=ws&host=${HOST}&path=${ENCODED_PATH}#Sing-Flare"


else

    echo "[INFO] HOST not configured"

    echo ""

    echo "Add HOST to .env to generate VLESS URI"

fi


echo ""

echo "=================================================="


# ==================================================
# Shutdown
# ==================================================

shutdown() {

    echo ""

    echo "[INFO] Stopping services"


    kill -TERM \
        "$SING_BOX_PID" \
        "$CLOUDFLARED_PID" \
        2>/dev/null \
        || true


    wait \
        "$SING_BOX_PID" \
        2>/dev/null \
        || true


    wait \
        "$CLOUDFLARED_PID" \
        2>/dev/null \
        || true


    exit 0

}


trap shutdown INT TERM


# ==================================================
# Monitor
# ==================================================

while true
do

    if ! kill -0 \
        "$SING_BOX_PID" \
        2>/dev/null
    then

        echo "[ERROR] sing-box stopped"

        shutdown

    fi


    if ! kill -0 \
        "$CLOUDFLARED_PID" \
        2>/dev/null
    then

        echo "[ERROR] cloudflared stopped"

        shutdown

    fi


    sleep 5

done
