#!/bin/sh

# testconfig: skip=1

# Check what are the differences (if any) between the golden xml cib and the new one
source ../../commonrc
source ../../inforc

# Compare one of this three:
# xml (result of pcs cluster cib)
# pcs (result of the conversion from cib to pcs commands)
# show (result of pcs config show)
compare=xml
overcloud_cib="overcloud-cib-$(date +%s)"
golden_cib="golden-cib"

# Generate the actual cib
case "$compare" in
 "xml"|"pcs") $SSH root@$CONTROLLER1 "pcs cluster cib" > $overcloud_cib\.xml
              # Generate the pcs command list
              clufter cib2pcscmd --nocheck -i $overcloud_cib\.xml | grep "^pcs" > $overcloud_cib\.pcs
              ;;
 "show") $SSH root@$CONTROLLER1 "pcs config show" > $overcloud_cib\.show
         ;;
 *) echo "No compare action parameter passed."
    exit 1
    ;;
esac

# Check the exit status
[ $? -ne 0 ] && echo "ERROR! Unable to generate cib." && exit 1

# Do the comparison
diff -c $golden_cib\.$compare $overcloud_cib\.$compare
[ $? -eq 0 ] && echo "OK. Overcloud cib is equal to golden." && exit 0 || echo "Error! Cib differs from golden." && exit 1
