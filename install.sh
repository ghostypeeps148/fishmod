#!/bin/bash

CURRENT_MAJOR=7
CURRENT_MINOR=0
CURRENT_VERSION=0

fishmod() {
    echo "Welcome to FISHMOD!"
    if [ -f /usr/local/fishmod ]; then
        echo "Fishmod appears to already be installed!"
        read -p "Delete old Fishmod installation? " answer
        case $answer in 
	        y) rm -rf /usr/local/fishmod;;
	        *) echo "Installation canceled."; exit;;
        esac
    fi
    cd /usr/local
    echo "Installing unzip..."
    # wow the murkmod installer came in handy
    arch=$(uname -m)
        case "$arch" in
          x86_64)
            busybox_url="https://raw.githubusercontent.com/shutingrz/busybox-static-binaries-fat/refs/heads/main/busybox-x86_64-linux-gnu" ;;
          aarch64)
            busybox_url="https://raw.githubusercontent.com/shutingrz/busybox-static-binaries-fat/refs/heads/main/busybox-aarch64-linux-gnu" ;;
          armv7l)
            busybox_url="https://raw.githubusercontent.com/shutingrz/busybox-static-binaries-fat/refs/heads/main/busybox-arm-linux-gnueabihf" ;;
          armv6l)
            busybox_url="https://raw.githubusercontent.com/shutingrz/busybox-static-binaries-fat/refs/heads/main/busybox-arm-linux-gnueabi" ;;
          mips)
            busybox_url="https://raw.githubusercontent.com/shutingrz/busybox-static-binaries-fat/refs/heads/main/busybox-mips-linux-gnu" ;;
          mips64)
            busybox_url="https://raw.githubusercontent.com/shutingrz/busybox-static-binaries-fat/refs/heads/main/busybox-mips64-linux-gnuabi64" ;;
          mipsel)
            busybox_url="https://raw.githubusercontent.com/shutingrz/busybox-static-binaries-fat/refs/heads/main/busybox-mipsel-linux-gnu" ;;
          mips64el)
            busybox_url="https://raw.githubusercontent.com/shutingrz/busybox-static-binaries-fat/refs/heads/main/busybox-mips64el-linux-gnuabi64" ;;
          powerpc64le)
            busybox_url="https://raw.githubusercontent.com/shutingrz/busybox-static-binaries-fat/refs/heads/main/busybox-powerpc64le-linux-gnu" ;;
          riscv32)
            busybox_url="https://raw.githubusercontent.com/shutingrz/busybox-static-binaries-fat/refs/heads/main/busybox-riscv32-linux-gnu" ;;
          riscv64)
            busybox_url="https://raw.githubusercontent.com/shutingrz/busybox-static-binaries-fat/refs/heads/main/busybox-riscv64-linux-gnu" ;;
          *)
            echo "Unsupported architecture: $arch"; exit 1 ;;
        esac
    curl --progress-bar -Lko /usr/local/tmp/bb "$busybox_url"
    chmod +x /usr/local/tmp/bb
    echo "Downloading fishmod to /usr/local/fishmod..."
    # ignore the temporary url
    curl --progress-bar -Lko /usr/local/fishmod.tar.gz https://example.com/fishmod.tar.gz
    # attempt unzip 
    /usr/local/tmp/bb tar x -z -f fishmod.tar.gz

    # cd into new directory
    cd /usr/local/fishmod
    echo "Fishmod installed!"
    /usr/local/fishmod/bin/show_logo.sh
    echo "Create fishmod folder..."
    # make fishmod folder
    mkdir /fsh
    mount --bind /usr/local/fishmod /fsh
    echo "Saving important data..."
    touch /fsh/cfg/murkmod_version
    echo "$CURRENT_MAJOR.$CURRENT_MINOR.$CURRENT_VERSION" > /fsh/cfg/murkmod_version
    # disable rootfs verification
    echo "Disabling rootfs verification..."
    /usr/share/vboot/bin/make_dev_ssd.sh -f --remove_rootfs_verification --partitions 2
    /usr/share/vboot/bin/make_dev_ssd.sh -f --remove_rootfs_verification --partitions 4 
    # start script
    echo "Checking sudo perms..."
    set_sudo_perms
    echo "Installing boot scripts..."
    install_patched_files
    echo "Backing up crosh for future fiish installation..."
    cp /usr/bin/crosh /fsh/bin/crosh
    cp /usr/bin/crosh.sh /fsh/bin/crosh.sh
    # note that fiish is actually installed in fishmod_bootstrap.conf through a mount
    read -p "Please enter a name for your Linux user." answer
    echo answer >> /fsh/user.txt

}

install() {
    TMP=$(mktemp)
    get_asset "$1" >"$TMP"
    if [ "$?" == "1" ] || ! grep -q '[^[:space:]]' "$TMP"; then
        echo "Failed to install $1 to $2"
        rm -f "$TMP"
        exit
    fi
    # Don't mv, that would break permissions
    cat "$TMP" >"$2"
    rm -f "$TMP"
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

install_patched_files() {
    install "chromeos_startup.sh" /sbin/chromeos_startup
    install "cr50-update.conf" /etc/init/cr50-update.conf
    install "fishmod_bootstrap.conf" /etc/init/fishmod_bootstrap.conf
    install "fishmod_user_session.conf" /etc/init/fishmod_user_session.conf
    install "pre-startup.conf" /etc/init/pre-startup.conf
    install "ssd_util.sh" /usr/share/vboot/bin/ssd_util.sh

    chmod 755 /sbin/chromeos_startup
    chmod 777 /usr/bin/crosh /usr/share/vboot/bin/ssd_util.sh 
}


set_sudo_perms() {
    if ! cat /etc/sudoers | grep chronos; then
        echo "Sudo permissions are not already set, setting..."
        echo "chronos ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers 
    else
        echo "Looks like sudo permissions are already set correctly."
    fi
}



if [ "$0" = "$BASH_SOURCE" ]; then
    if [ "$EUID" -ne 0 ]; then
        echo "Please run as root."
        exit
    fi
    fishmod
fi
