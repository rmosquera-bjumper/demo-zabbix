#!/bin/sh
set -e

API_URL="http://zabbix-web:8080/api_jsonrpc.php"

echo ">>> [1/6] Installing curl and jq..."
apk add --no-cache curl jq > /dev/null 2>&1

echo ">>> [2/6] Waiting for Zabbix Web API to respond..."
RETRY=0
MAX=60
until curl -sf -X POST "${API_URL}" \
    -H "Content-Type: application/json" \
    -d '{"jsonrpc":"2.0","method":"apiinfo.version","params":[],"id":1}' \
    > /dev/null 2>&1; do
    RETRY=$((RETRY + 1))
    [ "${RETRY}" -ge "${MAX}" ] && echo "ERROR: API not reachable after ${MAX} attempts" && exit 1
    echo "  Attempt ${RETRY}/${MAX} - waiting 5s..."
    sleep 5
done
echo "  API is reachable."

echo ">>> [3/6] Logging in to Zabbix API (Admin/zabbix)..."
RETRY=0
TOKEN=""
until [ -n "${TOKEN}" ] && [ "${TOKEN}" != "null" ]; do
    RETRY=$((RETRY + 1))
    [ "${RETRY}" -ge "${MAX}" ] && echo "ERROR: Login failed after ${MAX} attempts" && exit 1

    RESP=$(curl -sf -X POST "${API_URL}" \
        -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"user.login","params":{"username":"Admin","password":"zabbix"},"id":1}' \
        2>/dev/null || true)

    TOKEN=$(echo "${RESP}" | jq -r '.result // empty' 2>/dev/null || true)

    if [ -z "${TOKEN}" ] || [ "${TOKEN}" = "null" ]; then
        echo "  Attempt ${RETRY}/${MAX} - not ready yet, waiting 5s..."
        sleep 5
    fi
done
echo "  Login OK."

# Helper: Zabbix API call with Bearer token
zbx() {
    METHOD="$1"
    PARAMS="$2"
    curl -sf -X POST "${API_URL}" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer ${TOKEN}" \
        -d "{\"jsonrpc\":\"2.0\",\"method\":\"${METHOD}\",\"params\":${PARAMS},\"id\":1}"
}

# Helper: get or create a host group, returns groupid (logs go to stderr so
# they are not captured together with the ID)
get_or_create_group() {
    NAME="$1"
    EXISTING=$(zbx "hostgroup.get" "{\"filter\":{\"name\":[\"${NAME}\"]}}")
    ID=$(echo "${EXISTING}" | jq -r '.result[0].groupid // empty')
    if [ -z "${ID}" ]; then
        CREATED=$(zbx "hostgroup.create" "{\"name\":\"${NAME}\"}")
        ID=$(echo "${CREATED}" | jq -r '.result.groupids[0]')
        echo "  Created group '${NAME}': ${ID}" >&2
    else
        echo "  Found group '${NAME}': ${ID}" >&2
    fi
    echo "${ID}"
}

echo ">>> [4/6] Checking if hosts already configured..."
EXISTING_HOSTS=$(zbx "host.get" '{"search":{"host":"test-linux-1"},"limit":1}')
COUNT=$(echo "${EXISTING_HOSTS}" | jq '.result | length')
if [ "${COUNT}" -gt 0 ]; then
    echo "  Hosts already registered. Skipping setup."
    echo ">>> Done."
    exit 0
fi

echo ">>> [5/6] Setting up host groups and templates..."

# Host groups
LINUX_GROUP_ID=$(get_or_create_group "Linux servers")
TEST_GROUP_ID=$(get_or_create_group "Test Servers")
WEB_GROUP_ID=$(get_or_create_group "Web Servers")
ZABBIX_GROUP_ID=$(get_or_create_group "Zabbix servers")

# Templates
LINUX_TMPL=$(zbx "template.get" '{"output":["templateid","name"],"search":{"name":"Linux by Zabbix agent"}}')
LINUX_TMPL_ID=$(echo "${LINUX_TMPL}" | jq -r '.result[0].templateid // empty')
echo "  Linux template ID: ${LINUX_TMPL_ID}"

NGINX_TMPL=$(zbx "template.get" '{"output":["templateid","name"],"search":{"name":"Nginx by Zabbix agent"}}')
NGINX_TMPL_ID=$(echo "${NGINX_TMPL}" | jq -r '.result[0].templateid // empty')
echo "  Nginx template ID: ${NGINX_TMPL_ID}"

echo ">>> [6/6] Registering test hosts..."

# ── Update the default "Zabbix server" host to use Docker agent container ──
ZBX_HOST=$(zbx "host.get" '{"filter":{"host":"Zabbix server"},"selectInterfaces":["interfaceid","dns","ip"]}')
ZBX_HOST_ID=$(echo "${ZBX_HOST}" | jq -r '.result[0].hostid // empty')
ZBX_IF_ID=$(echo "${ZBX_HOST}" | jq -r '.result[0].interfaces[0].interfaceid // empty')

if [ -n "${ZBX_HOST_ID}" ] && [ -n "${ZBX_IF_ID}" ]; then
    zbx "hostinterface.update" "{
        \"interfaceid\": \"${ZBX_IF_ID}\",
        \"useip\": 0,
        \"ip\": \"\",
        \"dns\": \"zabbix-agent-server\",
        \"port\": \"10050\"
    }" > /dev/null
    echo "  Updated 'Zabbix server' interface -> zabbix-agent-server:10050"
fi

# ── test-linux-1 ──
TEMPLATES_LINUX="[]"
if [ -n "${LINUX_TMPL_ID}" ]; then
    TEMPLATES_LINUX="[{\"templateid\":\"${LINUX_TMPL_ID}\"}]"
fi

zbx "host.create" "{
    \"host\": \"test-linux-1\",
    \"name\": \"Test Linux Server 1\",
    \"interfaces\": [{
        \"type\": 1, \"main\": 1, \"useip\": 0,
        \"ip\": \"\", \"dns\": \"test-linux-1\", \"port\": \"10050\"
    }],
    \"groups\": [{\"groupid\":\"${TEST_GROUP_ID}\"},{\"groupid\":\"${LINUX_GROUP_ID}\"}],
    \"templates\": ${TEMPLATES_LINUX}
}" > /dev/null
echo "  Created: test-linux-1"

# ── test-linux-2 ──
zbx "host.create" "{
    \"host\": \"test-linux-2\",
    \"name\": \"Test Linux Server 2\",
    \"interfaces\": [{
        \"type\": 1, \"main\": 1, \"useip\": 0,
        \"ip\": \"\", \"dns\": \"test-linux-2\", \"port\": \"10050\"
    }],
    \"groups\": [{\"groupid\":\"${TEST_GROUP_ID}\"},{\"groupid\":\"${LINUX_GROUP_ID}\"}],
    \"templates\": ${TEMPLATES_LINUX}
}" > /dev/null
echo "  Created: test-linux-2"

# ── test-web-server ──
TEMPLATES_WEB="${TEMPLATES_LINUX}"
if [ -n "${NGINX_TMPL_ID}" ]; then
    TEMPLATES_WEB="[{\"templateid\":\"${LINUX_TMPL_ID}\"},{\"templateid\":\"${NGINX_TMPL_ID}\"}]"
fi

zbx "host.create" "{
    \"host\": \"test-web-server\",
    \"name\": \"Test Web Server (Nginx)\",
    \"interfaces\": [{
        \"type\": 1, \"main\": 1, \"useip\": 0,
        \"ip\": \"\", \"dns\": \"test-web-server\", \"port\": \"10050\"
    }],
    \"groups\": [{\"groupid\":\"${WEB_GROUP_ID}\"},{\"groupid\":\"${LINUX_GROUP_ID}\"}],
    \"templates\": ${TEMPLATES_WEB}
}" > /dev/null
echo "  Created: test-web-server (Nginx)"

echo ""
echo "============================================"
echo " Setup complete!"
echo " Zabbix UI : http://localhost:8080"
echo " Login     : Admin / zabbix"
echo " Test Web  : http://localhost:8081"
echo "============================================"
