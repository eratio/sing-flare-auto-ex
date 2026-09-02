#!/bin/sh

set -eu


# ==================================================
# sing-box
# ==================================================

if ! pgrep \
    -x \
    sing-box \
    > /dev/null
then

    echo "sing-box is not running"

    exit 1

fi


# ==================================================
# cloudflared
# ==================================================

if ! pgrep \
    -x \
    cloudflared \
    > /dev/null
then

    echo "cloudflared is not running"

    exit 1

fi


# ==================================================
# Configuration
# ==================================================

if [ ! -f /app/config.json ]; then

    echo "configuration missing"

    exit 1

fi


# ==================================================
# sing-box listener
# ==================================================

if ! ss \
    -lnt \
    | grep \
        -q "127.0.0.1:8080"
then

    echo "sing-box port is not listening"

    exit 1

fi


exit 0
