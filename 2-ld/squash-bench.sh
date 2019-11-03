#!/bin/sh

set -e

free_caches() {
  sudo sync
  printf "Freeing caches: "
  for i in 1 2 3; do 
      sudo sysctl -q vm.drop_caches="$i"
  done
  echo "done."
}

benchmark_startup() {
    SNAP="$1"
    APP="/snap/bin/$SNAP"
    case "$SNAP" in
        supertuxkart)
            NEEDLE="SuperTuxKart"
            ;;
        chromium)
            NEEDLE="New Tab - Chromium"
            ;;
        mari0)
            NEEDLE="Mari0"
            ;;
        gnome-calculator)
            NEEDLE="Calculator"
            ;;
        test-snapd-glxgears)
            NEEDLE="glxgears"
            ;;
        *)
            echo "EEE  No window name known for $SNAP; bailing out" >&2
            return 1
            ;;
    esac
    free_caches >&2

    start=$(date +%s%N)
    "$APP" &
    while ! wmctrl -l | grep -q "$NEEDLE"; do
        true
    done
    end=$(date +%s%N)
    TIME=$(( (end - start)/1000000 ))
    sleep 2
    # close window
    wmctrl -c "$NEEDLE"
    sleep 2
    # wait for window to disappear
    while wmctrl -l | grep -q "$NEEDLE"; do
        true
    done
    echo "$TIME"
}

bench() {
    # SNAP="$1"
    # MODE="$2"
    # ITER="$3"
    # if [ "$MODE" != "try" ]; then
    #     if [ "$MODE" != "xz" ]; then
    #         if [ ! -e "$SNAP-$MODE.snap" ]; then
    #             recompress "$SNAP" "$MODE" >&2
    #         fi
    #     fi
    #     sudo snap install --dangerous "$SNAP-$MODE.snap" >&2
    #     SIZE=$( stat -Lc%s "$SNAP-${MODE}.snap" )
    # else
    #     sudo snap try "$SNAP-root" >&2
    #     SIZE=$( du -bs "$SNAP-root" | cut -f1 )
    # fi

    # connect every interface declared
    # for iface in $(snap interfaces "$SNAP" 2>/dev/null | grep -P "^-" | awk '{print $2}'); 
    #     do snap connect "$iface" >&2
    # done

    START=$( benchmark_startup "$SNAP" )
    echo "$SNAP ($MODE): starting took ${START}ms" >&2

    START2=$( benchmark_startup "$SNAP" )
    echo "$SNAP ($MODE): 2nd start took ${START2}ms" >&2

    # sudo snap remove "$SNAP" >&2

    echo "$ITER:$SNAP:$MODE:$SIZE:$WALK:$WALK2"
}

# prepare() {
#     SNAP="$1"
#     if [ ! -d "$SNAP-root" ]; then
#         snap download "$SNAP"
#         sudo unsquashfs -d "$SNAP-root" "$SNAP"_*.snap
#         ln -sfv "$SNAP"_*.snap "$SNAP-xz.snap"
#     fi
#     if snap list "$SNAP" >/dev/null 2>&1; then
#         sudo snap remove "$SNAP"
#     fi
# }

if [ "$(id -u)" -eq 0 ]; then
    echo "ERROR! Must be a regular user."
    exit 1
fi

# Init
# snap version > log.txt
# echo "SNAP:MODE:SIZE:START:START2:WALK" >> log.txt
sudo true
if ! command -v wmctrl >/dev/null; then
    sudo apt install wmctrl
fi

for ITER in $(seq 1 4); do
    for SNAP in chromium; do
        echo "#### $SNAP ($ITER)"

        # for MODE in try xz none gzip lzo zstd; do
        #     echo "  ## $MODE"
            bench "$SNAP" "$MODE" "$ITER" | tee -a log.txt
        # done
    done
done

echo Finished
cat log.txt
