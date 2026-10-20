#!/bin/sh
# Idempotent: safe to run on every start. Creates the simulated sensor hosts
# and syncs the single connector managed by this project from STREAMING_*.
# Never prints the bearer token or the API session token.
set -e

API_URL="http://zabbix-web:8080/api_jsonrpc.php"
CONNECTOR_NAME="demo-zabbix-streaming"
SIM_GROUP="Simulated Sensors"
SIM_HOSTS="sim-sensor-01 sim-sensor-02 sim-sensor-03 sim-sensor-04 sim-sensor-05"
STREAM_TAG='{"tag":"stream","value":"demo"}'

echo ">>> [streaming 1/4] Installing curl and jq..."
apk add --no-cache curl jq > /dev/null 2>&1

echo ">>> [streaming 2/4] Logging in to Zabbix API (Admin/zabbix)..."
RETRY=0
MAX=60
TOKEN=""
until [ -n "${TOKEN}" ]; do
    RETRY=$((RETRY + 1))
    [ "${RETRY}" -ge "${MAX}" ] && echo "ERROR: Login failed after ${MAX} attempts" && exit 1
    TOKEN=$(curl -sf -X POST "${API_URL}" \
        -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"user.login","params":{"username":"Admin","password":"zabbix"},"id":1}' \
        2>/dev/null | jq -r '.result // empty' 2>/dev/null || true)
    [ -z "${TOKEN}" ] && echo "  Attempt ${RETRY}/${MAX} - not ready yet, waiting 5s..." && sleep 5
done
echo "  Login OK."

# Helper: Zabbix API call. Params must be valid JSON (built with jq).
# Prints .result; aborts the whole script on API errors (it usually runs
# inside $(...) or a pipeline, where a plain exit would only leave the subshell).
zbx() {
    BODY=$(jq -cn --arg m "$1" --argjson p "$2" '{jsonrpc:"2.0",method:$m,params:$p,id:1}')
    RESP=$(curl -sf -X POST "${API_URL}" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer ${TOKEN}" \
        -d "${BODY}") || { echo "ERROR: $1: HTTP request failed" >&2; kill -TERM $$; exit 1; }
    if [ "$(echo "${RESP}" | jq 'has("error")')" = "true" ]; then
        echo "ERROR: $1: $(echo "${RESP}" | jq -r '.error.data // .error.message')" >&2
        kill -TERM $$
        exit 1
    fi
    echo "${RESP}" | jq -c '.result'
}

echo ">>> [streaming 3/4] Syncing simulated sensor hosts..."
GROUP_ID=$(zbx "hostgroup.get" "$(jq -cn --arg n "${SIM_GROUP}" '{filter:{name:[$n]}}')" | jq -r '.[0].groupid // empty')
if [ -z "${GROUP_ID}" ]; then
    GROUP_ID=$(zbx "hostgroup.create" "$(jq -cn --arg n "${SIM_GROUP}" '{name:$n}')" | jq -r '.groupids[0]')
    echo "  Created group '${SIM_GROUP}'"
fi

# key|name|units|tags (sim.humidity has no stream tag: it proves the connector filter works)
ITEMS="sim.temperature|Temperature|°C|[${STREAM_TAG}]
sim.voltage|Voltage|V|[${STREAM_TAG}]
sim.humidity|Humidity|%|[]"

for HOST in ${SIM_HOSTS}; do
    HOST_ID=$(zbx "host.get" "$(jq -cn --arg h "${HOST}" '{filter:{host:[$h]},output:["hostid"]}')" | jq -r '.[0].hostid // empty')
    if [ -z "${HOST_ID}" ]; then
        HOST_ID=$(zbx "host.create" "$(jq -cn --arg h "${HOST}" --arg g "${GROUP_ID}" '{host:$h,groups:[{groupid:$g}]}')" | jq -r '.hostids[0]')
        echo "  Created host: ${HOST}"
    fi
    echo "${ITEMS}" | while IFS='|' read -r KEY NAME UNITS TAGS; do
        # type 2 = Zabbix trapper, value_type 0 = numeric float
        FIELDS=$(jq -cn --arg n "${NAME}" --arg u "${UNITS}" --argjson t "${TAGS}" \
            '{name:$n,type:2,value_type:0,units:$u,tags:$t}')
        ITEM_ID=$(zbx "item.get" "$(jq -cn --arg h "${HOST_ID}" --arg k "${KEY}" '{hostids:[$h],filter:{key_:[$k]},output:["itemid"]}')" | jq -r '.[0].itemid // empty')
        if [ -n "${ITEM_ID}" ]; then
            zbx "item.update" "$(echo "${FIELDS}" | jq -c --arg i "${ITEM_ID}" '. + {itemid:$i}')" > /dev/null
        else
            zbx "item.create" "$(echo "${FIELDS}" | jq -c --arg h "${HOST_ID}" --arg k "${KEY}" '. + {hostid:$h,key_:$k}')" > /dev/null
        fi
    done
done
echo "  5 hosts x 3 items in sync."

echo ">>> [streaming 4/4] Syncing connector '${CONNECTOR_NAME}'..."
EXISTING=$(zbx "connector.get" "$(jq -cn --arg n "${CONNECTOR_NAME}" '{filter:{name:[$n]},output:["connectorid","status"]}')")
if [ "$(echo "${EXISTING}" | jq 'length')" -gt 1 ]; then
    echo "ERROR: more than one connector named '${CONNECTOR_NAME}', fix it manually" && exit 1
fi
CONNECTOR_ID=$(echo "${EXISTING}" | jq -r '.[0].connectorid // empty')
CONNECTOR_STATUS=$(echo "${EXISTING}" | jq -r '.[0].status // empty')

case "$(echo "${STREAMING_ENABLED}" | tr '[:upper:]' '[:lower:]')" in
    1|true|yes|on) ENABLED=1 ;;
    *) ENABLED=0 ;;
esac

if [ "${ENABLED}" -eq 0 ]; then
    if [ -n "${CONNECTOR_ID}" ] && [ "${CONNECTOR_STATUS}" = "1" ]; then
        zbx "connector.update" "$(jq -cn --arg i "${CONNECTOR_ID}" '{connectorid:$i,status:0}')" > /dev/null
        ACTION="disabled"
    else
        ACTION="unchanged (streaming disabled)"
    fi
else
    if ! echo "${STREAMING_URL}" | grep -Eq '^https?://[^/?#]+'; then
        echo "ERROR: STREAMING_ENABLED=true requires a valid STREAMING_URL (http:// or https:// with a host)"
        exit 2
    fi
    if [ -n "${STREAMING_BEARER_TOKEN}" ]; then AUTHTYPE=5; BEARER="yes"; else AUTHTYPE=0; BEARER="no"; fi
    # data_type 0 = item values, item_value_type 1 = numeric float, operator 0 = equals,
    # authtype 5 = bearer. One sender: matches StartConnectors=1.
    FIELDS=$(jq -cn --arg url "${STREAMING_URL}" --arg tok "${STREAMING_BEARER_TOKEN}" --argjson auth "${AUTHTYPE}" \
        --argjson tag "${STREAM_TAG}" \
        '{url:$url,data_type:0,item_value_type:1,tags_evaltype:0,
          tags:[{tag:$tag.tag,operator:0,value:$tag.value}],
          max_senders:1,max_records:0,authtype:$auth,token:$tok,status:1,
          description:"Managed by init/setup-streaming.sh. Do not edit manually."}')
    echo "  Target: ${STREAMING_URL} (bearer: ${BEARER})"
    if [ -n "${CONNECTOR_ID}" ]; then
        zbx "connector.update" "$(echo "${FIELDS}" | jq -c --arg i "${CONNECTOR_ID}" '. + {connectorid:$i}')" > /dev/null
        ACTION="updated"
    else
        zbx "connector.create" "$(echo "${FIELDS}" | jq -c --arg n "${CONNECTOR_NAME}" '. + {name:$n}')" > /dev/null
        ACTION="created"
    fi
fi
echo "  Connector '${CONNECTOR_NAME}': ${ACTION}"
echo "  Changes apply on the next config cache reload (~${ZBX_CACHEUPDATEFREQUENCY:-10}s) or immediately with:"
echo "    docker exec zabbix-server zabbix_server -R config_cache_reload"
