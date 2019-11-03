#!/bin/sh -e

free_caches() {
  sudo sync
  printf "Freeing caches: "
  for i in 1 2 3; do 
      sudo sysctl -q vm.drop_caches="$i"
  done
  echo "done."
}


recompress_xz_block_dict() {
    set +e
    snap="$1"
    blocksize="$2"
    dictsize="$3"
    if [ "$dictsize" = "default" ]; then
        if ! mksquashfs "$snap-root" "$snap-xz-$dictsize-$blocksize.snap" -b "$blocksize" -noappend -no-fragments -all-root -no-xattrs -comp xz; then
            echo "ERROR: failed on blocksize=$blocksize dictsize=$dictsize for snap $snap"
            exit 1
        fi
    else
        if ! mksquashfs "$snap-root" "$snap-xz-$dictsize-$blocksize.snap" -b "$blocksize" -noappend -no-fragments -all-root -no-xattrs -comp xz -Xdict-size "$dictsize"; then
            echo "ERROR: failed on blocksize=$blocksize dictsize=$dictsize for snap $snap"
            exit 1
        fi
    fi
    set -e
}

recompress_xz_no_data_compression() {
    set +e
    snap="$1"
    if ! mksquashfs "$snap-root" "$snap-xz-no-d.snap" -noappend -no-fragments -all-root -no-xattrs -comp xz -noD; then
        echo "ERROR: failed on no data compression for snap $snap"
        exit 1
    fi
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
		APP="/snap/bin/test-snapd-glxgears.glxgears"
            ;;
        *)
            echo "EEE  No window name known for $SNAP; bailing out" >&2
            return 1
            ;;
    esac
    free_caches >&2

    start=$(date +%s%N)
    "$APP" >&2 2>/dev/null &
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
    sleep 1
    echo "$TIME"
}

benchmark_walk() {
    SNAP="$1"
    free_caches >&2

    start=$(date +%s%N)
    find "/snap/$SNAP/current/" -type f -print0 | xargs -0 md5sum >/dev/null
    end=$(date +%s%N)

    echo $(( (end - start)/1000000 ))
}


bench_snap_comp23() {
    SNAP="$1"
    #for blocksize in 4096; do
     #   for dictsize in default; do

    for blocksize in 4096 8192 16384 32768 65536 131072 262144 524288 1048576; do
        for dictsize in default 8192 16384 32768 65536 131072 262144 524288; do
            # if the block size is 4096 and the dictionary size isn't the default 
            if [ "$blocksize" = 4096 ] && [ "$dictsize" != default ]; then
                continue
            fi

            # if the dictionary is bigger than the blocksize, skip it too
            if [ "$dictsize" != "default" ]; then
                if [ "$dictsize" -gt "$blocksize" ]; then
                    continue
                fi
            fi

            free_caches >&2
            if [ -f "$SNAP-xz-$dictsize-$blocksize.snap" ]; then
                rm "$SNAP-xz-$dictsize-$blocksize.snap"
            fi

            start=$(date +%s%N)
            recompress_xz_block_dict "$SNAP" "$blocksize" "$dictsize"
            end=$(date +%s%N)
            SQUASH_TIME=$(( (end - start)/1000000 ))

            SIZE=$(stat -Lc%s "$SNAP-xz-$dictsize-$blocksize.snap")

            snap install "$SNAP-xz-$dictsize-$blocksize.snap" --dangerous

            # connect every interface declared
            for iface in $(snap interfaces "$SNAP" 2>/dev/null | grep -P "^-" | awk '{print $2}'); 
                do snap connect "$iface" >&2
            done

            START=$( benchmark_startup "$SNAP" )
            echo "$SNAP (blocksize=$blocksize, dictsize=$dictsize): starting took ${START}ms" >&2

            START2=$( benchmark_startup "$SNAP" )
            echo "$SNAP (blocksize=$blocksize, dictsize=$dictsize): 2nd start took ${START2}ms" >&2

            WALK=$( benchmark_walk "$SNAP" )
            echo "$SNAP (blocksize=$blocksize, dictsize=$dictsize): walk took ${WALK}ms" >&2

            snap remove chromium

            echo "$blocksize:$dictsize:$SQUASH_TIME:$SIZE:$START:$START2:$WALK" | tee -a squashfs-time-opts-log.txt
        done
    done
}

bench_no_d_snap_comp() {
    SNAP="$1"
    ITER="$2"
	echo "ITER is $ITER"
	echo "2 is $2"
    free_caches >&2
    if [ -f "$SNAP-xz-no-d.snap" ]; then
        rm "$SNAP-xz-no-d.snap"
    fi

    recompress_xz_no_data_compression "$SNAP"

    snap install "$SNAP-xz-no-d.snap" --dangerous

    # connect every interface declared
    for iface in $(snap interfaces "$SNAP" 2>/dev/null | grep -P "^-" | awk '{print $2}'); 
        do snap connect "$iface" >&2
    done

    START=$( benchmark_startup "$SNAP" )
    echo "$SNAP (nod): starting took ${START}ms" >&2

    START2=$( benchmark_startup "$SNAP" )
    echo "$SNAP (nod): 2nd start took ${START2}ms" >&2

    WALK=$( benchmark_walk "$SNAP" )
    echo "$SNAP (nod): walk took ${WALK}ms" >&2

    snap remove "$SNAP"

    echo "$ITER:nod:$SNAP:$START:$START2:$WALK" | tee -a squashfs-nod-time-opts-log2.txt
}

bench_snap_comp() {
    SNAP="$1"
    ITER="$2"
	echo "ITER is $ITER"
	echo "2 is $2"
    free_caches >&2
    if [ ! -f "$SNAP.snap" ]; then
	snap download "$SNAP" --basename="$SNAP"
	unsquashfs -d "$SNAP-root" "$SNAP.snap"
    fi

    snap install "$SNAP.snap" --dangerous

    # connect every interface declared
    for iface in $(snap interfaces "$SNAP" 2>/dev/null | grep -P "^-" | awk '{print $2}'); 
        do snap connect "$iface" >&2
    done

    START=$( benchmark_startup "$SNAP" )
    echo "$SNAP (d): starting took ${START}ms" >&2

    START2=$( benchmark_startup "$SNAP" )
    echo "$SNAP (d): 2nd start took ${START2}ms" >&2

    WALK=$( benchmark_walk "$SNAP" )
    echo "$SNAP (d): walk took ${WALK}ms" >&2

    snap remove "$SNAP"

    echo "$ITER:d:$SNAP:$START:$START2:$WALK" | tee -a squashfs-nod-time-opts-log2.txt
}

rm -f squashfs-nod-time-opts-log2.txt

for j in $(seq 1 10); do
	for snap in chromium supertuxkart mari0 gnome-calculator test-snapd-glxgears; do
		echo "iteration $j for snap $snap"
		bench_snap_comp "$snap" "$j"
		bench_no_d_snap_comp "$snap" "$j"
	done
done

