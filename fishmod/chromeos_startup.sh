#!/bin/bash

# R125 FIX: Prevent VT crashes during startup
# CRITICAL: Disable ALL VTs except VT1 during startup
# This prevents systemd-logind crashes

rm -f /fakemurk_startup_log
rm -r /fakemurk_startup_err
rm -f /fakemurk-log

touch /usr/local/fishmod/var/startup_log
chmod 775 /usr/local/fishmod/var/startup_log
exec 3>&1 1>> /usr/local/fishmod/var/startup_log 2>&1

# R125 FIX: Lock VT switching during critical operations
touch /run/murkmod-critical-startup

# R125 FIX: Stop systemd-logind to prevent conflicts
if pidof systemd-logind >/dev/null 2>&1; then
    systemctl stop systemd-logind.service 2>/dev/null || true
fi

# R125 FIX: Disable VT2-6 to prevent kernel panics
for vt in tty2 tty3 tty4 tty5 tty6; do
    if [ -c "/dev/$vt" ]; then
        chmod 000 "/dev/$vt" 2>/dev/null || true
    fi
done

# R125 FIX: Disable VT switching via kernel
if [ -f /sys/class/tty/tty0/active ]; then
    echo 1 > /sys/class/tty/tty0/active 2>/dev/null || true
fi

# Close stdin to prevent TTY conflicts
exec 0</dev/null

run_plugin() {
    bash "$1"
}

runjob() {
    # R125 FIX: Don't use clear - it can cause kernel panic
    trap 'kill -2 $! >/dev/null 2>&1' INT
    (
        # Run in subshell with safe redirects
        exec 0</dev/null
        exec 1>>/startup_log
        exec 2>&1
        # shellcheck disable=SC2068
        $@
    )
    trap '' INT
}

. /usr/share/misc/chromeos-common.sh
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
DST=$(get_largest_cros_blockdev)
if [ -z $DST ]; then
    DST=/dev/mmcblk0
fi
get_booted_kernnum() {
   if (($(cgpt show -n "$DST" -i 2 -P) > $(cgpt show -n "$DST" -i 4 -P))); then
	echo -n 2
   else
	echo -n 4
   fi
}

# we stage sshd and mkfs as a one time operation in startup instead of in the bootstrap script
# this is because ssh-keygen was introduced somewhere around R80, where many shims are still stuck on R73
# filesystem unfuck can only be done before stateful is mounted, which is perfectly fine in a shim but not if you run it while booted
# because mkfs is mean and refuses to let us format
# note that this will lead to confusing behaviour, since it will appear as if it crashed as a result of fakemurk
if [ ! -f /sshd_staged ]; then
    # thanks rory! <3
    echo "Staging sshd..."
    mkdir -p /ssh/root
    chmod -R 777 /ssh/root

    echo "Generating ssh keypair..."
    ssh-keygen -f /ssh/root/key -N '' -t rsa >/dev/null
    cp /ssh/root/key /rootkey
    chmod 600 /ssh/root
    chmod 644 /rootkey

    echo "Creating config..."
    cat >/ssh/config <<-EOF
AuthorizedKeysFile /ssh/%u/key.pub
StrictModes no
HostKey /ssh/root/key
Port 1337
EOF

    touch /sshd_staged
    echo "Staged sshd."
fi

echo "Launching sshd..."
/usr/sbin/sshd -f /ssh/config &

if [ -f /logkeys/active ]; then
    echo "Found logkeys flag, launching..."
    /usr/bin/logkeys -s -m /logkeys/keymap.map -o /mnt/stateful_partition/keylog
fi

if [ ! -f /usr/local/fishmod/var/.stateful_unfucked ]; then
    echo "Unfucking stateful..."
    yes | mkfs.ext4 "${DST}p1"
    touch /usr/local/fishmod/var/.stateful_unfucked
    echo "Done, rebooting..."
    reboot
else
    echo "Stateful already unfucked, doing temp stateful mount..."
    stateful_dev=${DST}p1
    first_mount_dir=$(mktemp -d)
    
    # R125 FIX: Extra safety during mount
    echo "Mounting stateful (VT2 unsafe during this operation)..."
    mount "$stateful_dev" "$first_mount_dir"
    echo "Mounted stateful on $first_mount_dir, looking for startup plugins..."

    plugin_dir="$first_mount_dir/murkmod/plugins"
    temp_dir=$(mktemp -d)

    cp -r "$plugin_dir"/* "$temp_dir" 2>/dev/null || true
    echo "Copied files to $temp_dir, unmounting and cleaning up..."

    # R125 FIX: Ensure unmount completes before proceeding
    umount "$stateful_dev"
    sync
    rmdir "$first_mount_dir"
    echo "Stateful unmounted safely."

    echo "Finding startup plugins..."
    for file in "$temp_dir"/*.sh; do
        if grep -q "startup_plugin" "$file"; then
            echo "Starting plugin $file..."
            runjob run_plugin $file
        fi
    done

    /usr/share/vboot/bin/make_dev_ssd.sh -f --remove_rootfs_verification --partitions 2
    /usr/share/vboot/bin/make_dev_ssd.sh -f --remove_rootfs_verification --partitions 4 
    
    # R125 FIX: Re-enable VTs now that critical operations are done
    echo "Re-enabling VT2-6..."
    for vt in tty2 tty3 tty4 tty5 tty6; do
        if [ -c "/dev/$vt" ]; then
            chmod 620 "/dev/$vt" 2>/dev/null || true
        fi
    done
    
    # R125 FIX: Restart systemd-logind
    systemctl start systemd-logind.service 2>/dev/null || true
    
    # R125 FIX: Remove critical startup flag
    rm -f /run/murkmod-critical-startup
    
    # R125 FIX: Signal that startup is complete and VT2 is safe
    touch /usr/local/fishmod/var/run/murkmod-startup-complete
    chmod 644 /var/run/murkmod-startup-complete
    
    echo "Plugins run. VT2 now safe to use. Handing over to real startup..."
    if [ ! -f /new-startup ]; then
        exec /sbin/chromeos_startup.sh.old
    else 
        exec /sbin/chromeos_startup.old
    fi
fi
