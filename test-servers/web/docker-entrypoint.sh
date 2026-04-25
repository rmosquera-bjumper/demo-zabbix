#!/bin/sh
# Start nginx as a background daemon
nginx
echo "Nginx started."

# Hand off to the official Zabbix Agent2 entrypoint
exec /usr/bin/docker-entrypoint.sh "$@"
