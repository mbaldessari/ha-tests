#!/bin/sh
set -e

source ../../commonrc
source ../../inforc

FAILURES=0
MSG=""

# Fetch all the systemd services managed via pcs
pcs_services=$($SSH root@$CONTROLLER1 "pcs resource show --full |grep 'Resource:' | grep systemd | grep -E -o 'type=[a-zA-Z0-9-]*' | cut -f2 -d\=")

for i in $($SSH root@$CONTROLLER1 "systemctl list-unit-files | grep service | grep enabled | awk '{ gsub(\".service\",\"\",\$1); print \$1 }'"); do
    for j in $pcs_services; do
        if [[ $i == $j ]]; then
            MSG="$MSG $i"
            FAILURES=$((FAILURES + 1))
        fi 
    done
done

   
if [ ${FAILURES} -ne 0 ]; then
    echo "CRITICAL enabled systemd services found [$FAILURES]:$MSG"
    exit 1
else
    exit 0
fi
