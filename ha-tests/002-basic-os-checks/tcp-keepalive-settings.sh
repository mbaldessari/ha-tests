#!/bin/sh
set -e

source ../../commonrc
source ../../inforc

#net.ipv4.tcp_keepalive_intvl = 1
#net.ipv4.tcp_keepalive_probes = 5
#net.ipv4.tcp_keepalive_time = 5

FAILURES=0
MSG=""
INTVL=$($SSH root@$CONTROLLER1 "sysctl -n net.ipv4.tcp_keepalive_intvl")
PROBES=$($SSH root@$CONTROLLER1 "sysctl -n net.ipv4.tcp_keepalive_probes")
TIME=$($SSH root@$CONTROLLER1 "sysctl -n net.ipv4.tcp_keepalive_time")

if [ ${INTVL} -ne 1 ]; then
    FAILURES=$((FAILURES + 1))
    MSG="$MSG - tcp_keepalive_intvl"
fi
if [ ${PROBES} -ne 5 ]; then
    FAILURES=$((FAILURES + 1))
    MSG="$MSG - tcp_keepalive_probe"
fi
if [ ${TIME} -ne 5 ]; then
    FAILURES=$((FAILURES + 1))
    MSG="$MSG - tcp_keepalive_time"
fi
   
if [ ${FAILURES} -ne 0 ]; then
    echo "CRITICAL failed sysctl: $MSG"
    exit 1
else
    exit 0
fi
