#!/bin/sh

# BZ https://bugzilla.redhat.com/show_bug.cgi?id=1259013
source ../../commonrc
source ../../inforc

$SSH root@$CONTROLLER1 "crm_mon --one-shot | grep --quiet Failed"
STATUS=$?
if [ ${STATUS} -eq 0 ]; then
    DETAILS=$($SSH root@$CONTROLLER1 "crm_mon --one-shot | awk '/Failed/ {f=1}f' | grep --invert-match Failed")
    echo "CRITICAL failed resources: $DETAILS"
    exit 1
else 
    exit 0
fi
