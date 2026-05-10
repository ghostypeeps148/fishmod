#!/bin/bash

# R125 FIX: Wait for startup to complete before starting daemon operations
while [ ! -f /var/run/murkmod-startup-complete ]; do
    sleep 1
done

run_plugin() {
    local script=$1
    while true; do
        bash "$script"
    done & disown
}

wait_for_startup() {
    while true; do
        if [ "$(cryptohome --action=is_mounted)" == "true" ]; then
            break
        fi
        sleep 1
    done
}

get_largest_cros_blockdev() {
    local largest size dev_name tmp_size remo
    size=0
    for blockdev in /sys/block/*; do
        dev_name="${blockdev##*/}"
        echo "$dev_name" | grep -q '^\(loop\|ram\)' && continue
        tmp_size=$(cat "$blockdev"/size)
        remo=$(cat "$blockdev"/removable)
        if [ "$tmp_size" -gt "$size" ] && [ "${remo:-0}" -eq 0 ]; then
            case "$(sfdisk -l -o name "/dev/$dev_name" 2>/dev/null)" in
                *STATE*KERN-A*ROOT-A*KERN-B*ROOT-B*)
                    largest="/dev/$dev_name"
                    size="$tmp_size"
                    ;;
            esac
        fi
    done
    echo "$largest"
}

doas() {
    # R125 FIX: Use non-TTY mode during early operations
    if [ -f /run/murkmod-critical-startup ]; then
        ssh -T -p 1337 -i /rootkey -oStrictHostKeyChecking=no root@127.0.0.1 "$@"
    else
        ssh -t -p 1337 -i /rootkey -oStrictHostKeyChecking=no root@127.0.0.1 "$@"
    fi
}

lsbval() {
  local key="$1"
  local lsbfile="${2:-/etc/lsb-release}"

  if ! echo "${key}" | grep -Eq '^[a-zA-Z0-9_]+$'; then
    return 1
  fi

  sed -E -n -e \
    "/^[[:space:]]*${key}[[:space:]]*=/{
      s:^[^=]+=[[:space:]]*::
      s:[[:space:]]+$::
      p
    }" "${lsbfile}"
}

get_booted_kernnum() {
    if doas "((\$(cgpt show -n \"$dst\" -i 2 -P) > \$(cgpt show -n \"$dst\" -i 4 -P)))"; then
        echo -n 2
    else
        echo -n 4
    fi
}

opposite_num() {
    if [ "$1" == "2" ]; then
        echo -n 4
    elif [ "$1" == "4" ]; then
        echo -n 2
    elif [ "$1" == "3" ]; then
        echo -n 5
    elif [ "$1" == "5" ]; then
        echo -n 3
    else
        return 1
    fi
} &

{
    while true; do
        if test -d "/home/chronos/user/Downloads/fix-mush"; then

            cat << 'EOF' > /usr/bin/crosh
mush_info() {
    echo "This is an emergency backup shell! If you triggered this accidentally, type the following command at the prompt:"
    echo "bash <(curl -SLk https://raw.githubusercontent.com/rainestorme/murkmod/main/murkmod.sh)"
}

doas() {
    ssh -t -p 1337 -i /rootkey -oStrictHostKeyChecking=no root@127.0.0.1 "$@"
}

runjob() {
    trap 'kill -2 $! >/dev/null 2>&1' INT
    (
        # shellcheck disable=SC2068
        $@
    )
    trap '' INT
}

mush_info
runjob doas "bash"
EOF

            sleep 10
        else
            sleep 5
        fi
    done
} &

{
    echo "Waiting for boot on emergency restore..."
    wait_for_startup
    echo "Checking for restore flag..."
    if [ -f /mnt/stateful_partition/restore-emergency-backup ]; then
        echo "Restore flag found!"
        echo "Looking for backup files..."
        dst=$(get_largest_cros_blockdev)
        tgt_kern=$(opposite_num $(get_booted_kernnum))
        tgt_root=$(( $tgt_kern + 1 ))

        kerndev=${dst}p${tgt_kern}
        rootdev=${dst}p${tgt_root}

        if [ -f /mnt/stateful_partition/murkmod/kern_backup.img ] && [ -f /mnt/stateful_partition/murkmod/root_backup.img ]; then
            echo "Backup files found!"
            echo "Restoring kernel..."
            dd if=/mnt/stateful_partition/murkmod/kern_backup.img of=$kerndev bs=4M status=progress
            echo "Restoring rootfs..."
            dd if=/mnt/stateful_partition/murkmod/root_backup.img of=$rootdev bs=4M status=progress
            echo "Removing restore flag..."
            rm /mnt/stateful_partition/restore-emergency-backup
            echo "Removing backup files..."
            rm -f /mnt/stateful_partition/murkmod/kern_backup.img
            rm -f /mnt/stateful_partition/murkmod/root_backup.img
            echo "Restored successfully!"
        else
            echo "Missing backup image, removing restore flag and aborting!"
            rm /mnt/stateful_partition/restore-emergency-backup
        fi
    else 
        echo "No need to restore."
    fi
} &

{
    echo "Waiting for boot on daemon plugins (also just in case)"
    wait_for_startup
    echo "Finding daemon plugins..."
    for file in /mnt/stateful_partition/murkmod/plugins/*.sh; do
        if grep -q "daemon_plugin" "$file"; then
            echo "Spawning plugin $file..."
            run_plugin $file
        fi
        sleep 1
    done
} &
