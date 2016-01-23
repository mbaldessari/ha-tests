#!/bin/sh

# BZ: https://bugzilla.redhat.com/show_bug.cgi?id=1262263
# testconfig: timeout=20m
# testconfig: skip=1

source ../../commonrc
source ../../inforc

TIMEOUT=120
WAITTIME=10

# This test will do a clean reboot of each controller node

# reboot normally controller X
function reboot_node() {
    node=$1

    echo "Rebooting $node"
    btime=$(btimec $node | awk '{print $2}')
    if [[ $btime == 0 ]]; then
        echo "$node btime is 0. Is the node even up?"
        exit 1
    fi
    $SSH root@$node "reboot"
    # Give the node some time to go down
    sleep $WAITTIME
  
    # This is okay for now as runner.sh calls us with a timeout
    # so it is not a big deal and we will fail in case of timeout
    while ! ping -c 1 $node -w 5 > /dev/null 
    do 
        echo -n "."
    done
    echo "."
    echo -n "$node is back, waiting for btimed to start..."
    newbtime=$(btimec $node | awk '{print $2}')
    while [[ $newbtime == 0 ]]
    do
        newbtime=$(btimec $node | awk '{print $2}')
        echo -n "."
    done
    echo "."
    echo "$node btime is now {$newbtime}"

    if [[ $btime == $newbtime ]]
    then
        echo "$node was not rebooted"
        exit 1
    fi

    # At this point the node is back up
}

function wait_for_pcs_online {
    controller=$1

    echo "Waiting for $controller"
    TIME=0
    while [[ $TIME < $TIMEOUT ]]
    do
        $SSH root@$controller "pcs status pcsd | grep Offline"
        STATUS=$?
        if [ ${STATUS} -eq 0 ]; then
            # A node is still down we need to wait
            sleep 1
        else
            # All nodes are back up and online
            break
        fi
    done
}

reboot_node $CONTROLLER1
wait_for_pcs_online $CONTROLLER1

reboot_node $CONTROLLER2
wait_for_pcs_online $CONTROLLER2

reboot_node $CONTROLLER3
wait_for_pcs_online $CONTROLLER3

$SSH root@$CONTROLLER1 "pcs status pcsd | grep Offline"
STATUS=$?
if [ ${STATUS} -eq 0 ]; then
    echo "CRITICAL still nodes offline"
    exit 1
fi

$SSH root@$CONTROLLER1 "crm_mon --one-shot | grep --quiet Failed"
STATUS=$?
if [ ${STATUS} -eq 0 ]; then
    DETAILS=$($SSH root@$CONTROLLER1 "crm_mon --one-shot | awk '/Failed/ {f=1}f' | grep --invert-match Failed")
    echo "CRITICAL failed resources: $DETAILS"
    exit 1
fi

exit 0
