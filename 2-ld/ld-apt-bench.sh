#!/bin/bash

set -e

free_caches() {
  sudo sync
  printf "Freeing caches: "
  for i in 1 2 3; do 
      sudo sysctl -q vm.drop_caches="$i"
  done
  sudo rm /etc/ld.so.cache
  sudo touch /etc/ld.so.cache
  echo "done."
}

benchmark_startup() {
    DEB="$1"
    case "$DEB" in
        chromium-browser)
            NEEDLE="New Tab - Chromium"
            APP="/usr/bin/chromium-browser"
            ;;
        *)
            echo "EEE  No window name known for $SNAP; bailing out" >&2
            return 1
            ;;
    esac
    free_caches >&2

    start=$(date +%s%N)
    export LD_DEBUG=libs
    "$APP" >app-$RANDOM.log 2>&1 &
    LD_DEBUG=
    while ! wmctrl -l | grep -q "$NEEDLE"; do
        true
    done
    end=$(date +%s%N)
    TIME=$(( (end - start)/1000000 ))
    sleep 3
    # close window
    wmctrl -c "$NEEDLE"
    sleep 3
    # wait for window to disappear
    while wmctrl -l | grep -q "$NEEDLE"; do
        true
    done
    echo "$TIME"
}

bench() {
    DEB="$1"
    ITER="$2"
    sudo apt install -y -qq "$DEB" >&2

    START=$( benchmark_startup "$DEB" )
    echo "$DEB : starting took ${START}ms" >&2

    START2=$( benchmark_startup "$DEB" )
    echo "$DEB : starting 2nd time took ${START2}ms" >&2

    START3=$( benchmark_startup "$DEB" )
    echo "$DEB : starting 3rd time took ${START3}ms" >&2
    
    echo "$ITER:$DEB:$START:$START2:$START3"
}

prepare() {
    DEB="$1"
    # remove it if it's installed
    if dpkg -l | grep -q "$DEB"; then
        sudo apt remove -y -qq "$DEB"
    fi
}

if [ "$(id -u)" -eq 0 ]; then
    echo "ERROR! Must be a regular user."
    exit 1
fi

sudo true
if ! command -v wmctrl >/dev/null; then
    sudo apt install wmctrl
fi

for ITER in $(seq 1 10); do
    for DEB in chromium-browser; do
        echo "#### $DEB"
        prepare "$DEB"
        bench "$DEB" "$ITER" | tee -a log.txt
    done
done

echo Finished
cat log.txt
