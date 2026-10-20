#!/bin/sh
# Sends simulated sensor readings to Zabbix trapper items with zabbix_sender.
# Destination is always the Zabbix Server; the stream receiver only gets data
# through Zabbix's native streaming connector.

ZABBIX_SERVER="${ZABBIX_SERVER:-zabbix-server}"
SIM_INTERVAL="${SIM_INTERVAL:-10}"
HOSTS="sim-sensor-01 sim-sensor-02 sim-sensor-03 sim-sensor-04 sim-sensor-05"
BATCH=/tmp/sensor-batch.txt

echo "Sending to ${ZABBIX_SERVER}:10051 every ${SIM_INTERVAL}s"
while true; do
    # zabbix_sender input format: <host> <key> <value>
    awk -v hosts="${HOSTS}" -v seed="$(date +%s)" 'BEGIN {
        srand(seed)
        n = split(hosts, h, " ")
        for (i = 1; i <= n; i++) {
            printf "%s sim.temperature %.2f\n", h[i], 20 + rand() * 10
            printf "%s sim.voltage %.2f\n",     h[i], 225 + rand() * 10
            printf "%s sim.humidity %.2f\n",    h[i], 40 + rand() * 20
        }
    }' > "${BATCH}"
    zabbix_sender -z "${ZABBIX_SERVER}" -i "${BATCH}" | tail -1
    sleep "${SIM_INTERVAL}"
done
