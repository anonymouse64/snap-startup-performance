#!/bin/sh 

date +%s%N > "$SNAP_USER_DATA/start"
# end=$(date +%s%N)

# TIME=$(( (end - start)/1000000 ))

exec "$@"
