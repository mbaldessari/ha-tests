#!/bin/sh

source ../../commonrc
source ../../inforc

overcloud_cib="overcloud-cib-$(date +%s).xml"
golden_cib="golden-cib.xml"

$SSH root@$CONTROLLER1 "pcs cluster cib" > $overcloud_cib
../../cibdiff/cibdiff.py --cimode $golden_cib $overcloud_cib
