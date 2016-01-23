#!/bin/sh

source ../../commonrc
source ../../inforc

#FIXME: Current FD value needs to be checked or read dynamically
RABBITFD=3996

CMD='rabbitmqctl report | grep -A3 file_descriptors |grep total_limit |uniq |cut -f3 -d ","|cut -f1 -d "}"'

for i in $CONTROLLER1 $CONTROLLER2 $CONTROLLER3; do
    OUT=$($SSH root@$i "$CMD")
    if [ ${OUT} -ne $RABBITFD ]; then
        echo "CRITICAL: Unexpected fd number for rabbit ${OUT} on $i"
        exit 1
    fi
done

exit 0
