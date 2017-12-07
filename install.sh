#
# install.sh
#   FreeBSD ZFS custom installation script for use with bsdinstall.
#
# Usage
#   First, copy/create/edit *.cfg.sample to whatyoulike.cfg
#   on a host such as your laptop.
#
#   Then spin up web server on the host.
#   One way to do this is running the following command in
#   the directory containing this script and config files.
#
#     python -m SimpleHTTPServer
#
#   Finally on the target host, do something like the following
#   at the FreeBSD installer's shell prompt.
#   (Assume that 192.168.10.120 is your laptop.)
#
#     dhclient em0
#     cd /tmp
#     fetch http://192.168.10.120:8000/install.sh
#     fetch http://192.168.10.120:8000/whatyoulike.cfg
#     export CUSTOM_CONFIG_FILE=whatyoulike.cfg
#     bsdinstall script install.sh
#     less bsdinstall_log
#     reboot

####################################################
# PREAMBLE
####################################################

. ${CUSTOM_CONFIG_DIR:-/tmp}/${CUSTOM_CONFIG_FILE:=install.cfg}

: ${CUSTOM_CONFIG_BASEURL:=http://192.168.10.120:8000}
: ${DISTRIBUTIONS:=base.txz kernel.txz}
: ${ZFSBOOT_DISKS:=ada0}
: ${ZFSBOOT_VDEV_TYPE:=stripe}
: ${ZFSBOOT_SWAP_SIZE:=0}
: ${ZFSBOOT_POOL_CREATE_OPTIONS:=-O compression=lz4 -O atime=off -O com.sun:auto-snapshot=true}
: ${ZFSBOOT_POOL_NAME:=zroot}
: ${ZFSBOOT_BEROOT_NAME:=ROOT}
: ${ZFSBOOT_BOOTFS_NAME:=default}
: ${ZFSBOOT_GELI_ENCRYPTION=}
if [ -z "$ZFSBOOT_DATASETS" ]; then
	ZFSBOOT_DATASETS="
	# DATASET	OPTIONS (comma or space separated; or both)

	# Boot Environment [BE] root and default boot dataset
	/$ZFSBOOT_BEROOT_NAME				mountpoint=none
	/$ZFSBOOT_BEROOT_NAME/$ZFSBOOT_BOOTFS_NAME	mountpoint=/

	# Compress /tmp, allow exec but not setuid
	# Omit from auto snapshot
	/tmp		mountpoint=/tmp,exec=on,setuid=off,com.sun:auto-snapshot=false

	# Don't mount /usr so that 'base' files go to the BEROOT
	/usr		mountpoint=/usr,canmount=off

	# Don't mount /usr/local too for the same reason.
	/usr/local	canmount=off

	# Home directories separated so they are common to all BEs
	/home		mountpoint=/home

	# Ports tree
	/usr/ports	setuid=off,com.sun:auto-snapshot=false

	# Source tree (compressed)
	/usr/src	com.sun:auto-snapshot=false
	/usr/obj	com.sun:auto-snapshot=false

	# Create /var and friends
	/var		mountpoint=/var,canmount=off
	/var/audit	exec=off,setuid=off
	/var/crash	exec=off,setuid=off,com.sun:auto-snapshot=false
	/var/log	exec=off,setuid=off
	/var/mail	atime=on
	/var/tmp	setuid=off,com.sun:auto-snapshot=false
" # END-QUOTE
fi

### DISTRIBUTIONS is exported from /usr/libexec/bsdinstall/script.

export nonInteractive="YES"
export CUSTOM_CONFIG_FILE
export CUSTOM_CONFIG_BASEURL
export ZFSBOOT_DISKS
export ZFSBOOT_VDEV_TYPE
export ZFSBOOT_SWAP_SIZE
export ZFSBOOT_POOL_CREATE_OPTIONS
export ZFSBOOT_POOL_NAME
export ZFSBOOT_BEROOT_NAME
export ZFSBOOT_BOOTFS_NAME
export ZFSBOOT_GELI_ENCRYPTION
export ZFSBOOT_DATASETS



####################################################
# POST INSTALLATION SETUP
####################################################

#!/bin/sh

#
# void load_script <filename>
#
load_script(){
	local filename="$1"
	if [ -n "$filename" ]; then
		cd /tmp
		fetch ${CUSTOM_CONFIG_BASEURL}/${filename}
		. ./${filename}
	fi
}

#
# Load default configuration file.
#
load_script "${CUSTOM_CONFIG_FILE}"

: ${HOSTNAME:=freebsd}
: ${KEYMAP:=jp}
: ${NIC_LIST=em0}
: ${IP_LIST=192.168.10.5}
: ${NETMASK_LIST=255.255.255.0}
: ${DEFAULTROUTER=192.168.10.1}
: ${SEARCHDOMAINS=example.com}
: ${NAMESERVER_LIST=192.168.10.1}
: ${DEFAULT_ROOT_PASSWORD:=root}
: ${DEFAULT_USER_GROUP_NAME:=users}
: ${DEFAULT_USER_GROUP_ID:=100}
: ${DEFAULT_USER_NAME:=freebsd}
: ${DEFAULT_USER_ID:=500}
: ${DEFAULT_USER_PASSWORD:=freebsd}
: ${SSH_PERMIT_ROOT_LOGIN_IPRANGE=192.168.10.0/24,127.0.0.0/8}
: ${TIME_ZONE:=Asia/Tokyo}
: ${PROXY_SERVER=}
: ${PKG_LIST=beadm sudo zfstools}
: ${ZVOL_SWAP_SIZE:=2G}

#
# Run optional pre script.
#
load_script "$OPTIONAL_SCRIPT_PRE"



##########
# First snapshot. No configuration customized yet.
##########
zfs snapshot -r ${ZFSBOOT_POOL_NAME}/${ZFSBOOT_BEROOT_NAME}/${ZFSBOOT_BOOTFS_NAME}@install-00dist

#
# Is this on a virtual environment (hypervisor)?
#
hv=$(sysctl -n kern.vm_guest)

#
# /etc/sysctl.conf
#
if [ -n "$hv" ]; then
	sysrc -f /etc/sysctl.conf net.inet.tcp.tso=0
fi

#
# /boot/loader.conf
#
sysrc -f /boot/loader.conf beastie_disable="NO"
sysrc -f /boot/loader.conf autoboot_delay="3"

if [ -n "$hv" ]; then
	sysrc -f /boot/loader.conf console="vidconsole,comconsole"
fi

#
# /etc/rc.conf
#
sysrc zfs_enable="YES"
sysrc hostname="${HOSTNAME}"
sysrc keymap="${KEYMAP}"
sysrc defaultrouter="${DEFAULTROUTER}"
sysrc sshd_enable="YES"
sysrc dumpdev="NO"

if [ "xen" = "$hv" ]; then
	sysrc xenguest_enable="YES"
	sysrc xe_daemon_enable="YES"
fi

if [ -n "$hv" ]; then
	ifopt=" -tso"
else
	ifopt=""
fi

i=1
for nic in $NIC_LIST; do
	ip=`echo $IP_LIST | cut -d " " -f $i`
	mask=`echo $NETMASK_LIST | cut -d " " -f $i`
	sysrc ifconfig_${nic}="inet $ip netmask ${mask:-255.255.255.0}${ifopt}"
	i=`expr "$i" + 1`
done

#
# /etc/resolv.conf
#
touch /etc/resolv.conf
cat <<EOF>> /etc/resolv.conf
search ${SEARCHDOMAINS}
EOF

for nameserver in $NAMESERVER_LIST; do
	echo "nameserver ${nameserver}" >> /etc/resolv.conf
done

#
# /etc/ssh/sshd_config
#
cat <<EOF>> /etc/ssh/sshd_config
KexAlgorithms curve25519-sha256@libssh.org,ecdh-sha2-nistp256,ecdh-sha2-nistp384,ecdh-sha2-nistp521,diffie-hellman-group-exchange-sha256,diffie-hellman-group-exchange-sha1,diffie-hellman-group14-sha1,diffie-hellman-group1-sha1
EOF

if [ -n "${SSH_PERMIT_ROOT_LOGIN_IPRANGE}" ]; then
	cat <<EOF>> /etc/ssh/sshd_config

Match Address ${SSH_PERMIT_ROOT_LOGIN_IPRANGE}
	PermitRootLogin yes
EOF
fi

#
# Timezone
#
cp /usr/share/zoneinfo/${TIME_ZONE} /etc/localtime

#
# ZFS Pool's root dataset has no need to be mounted.
#
zfs set mountpoint=none ${ZFSBOOT_POOL_NAME}

#
# User configurations
#
echo ${DEFAULT_ROOT_PASSWORD} | pw usermod root -h 0 -s /bin/tcsh
pw groupadd -n ${DEFAULT_USER_GROUP_NAME} -g ${DEFAULT_USER_GROUP_ID}
echo ${DEFAULT_USER_PASSWORD} | pw useradd -n ${DEFAULT_USER_NAME} -u ${DEFAULT_USER_ID} -g ${DEFAULT_USER_GROUP_NAME} -h 0 -m -s /bin/tcsh
pw groupmod -n wheel -m ${DEFAULT_USER_NAME}

#
# Shell configuration
#
cat <<EOF> /cshrc.addon

alias rm rm -i
alias mv mv -i
alias cp cp -i
alias ls ls -Fw

set noclobber
set ignoreeof
EOF

if [ -n "${PROXY_SERVER}" ]; then
	cat <<EOF>> /cshrc.addon

setenv http_proxy ${PROXY_SERVER}
setenv https_proxy ${PROXY_SERVER}
setenv ftp_proxy ${PROXY_SERVER}
EOF

	export http_proxy=${PROXY_SERVER}
	export https_proxy=${PROXY_SERVER}
	export ftp_proxy=${PROXY_SERVER}
fi

cat /cshrc.addon >> /root/.cshrc
cat /cshrc.addon >> /home/${DEFAULT_USER_NAME}/.cshrc
rm /cshrc.addon

#
# crontabs
#
if [ ! -d /etc/cron.d ]; then
	mkdir -p /etc/cron.d
fi
cat <<'EOF'> /etc/cron.d/00zfstools
#
# Added for zfs-auto-snapshot(zfstools)
#
PATH=/etc:/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin
15,30,45 * * * * root /usr/local/sbin/zfs-auto-snapshot 15min     4
0        * * * * root /usr/local/sbin/zfs-auto-snapshot hourly   24
7        0 * * * root /usr/local/sbin/zfs-auto-snapshot daily     7
14       0 * * 7 root /usr/local/sbin/zfs-auto-snapshot weekly    4
28       0 1 * * root /usr/local/sbin/zfs-auto-snapshot monthly  12
EOF

#
# periodic.conf
#
sysrc -f /etc/periodic.conf daily_status_zfs_enable="YES"

#
# sudoers
#
if [ ! -d /usr/local/etc/sudoers.d ]; then
	mkdir -p /usr/local/etc/sudoers.d
fi
cat <<EOF> /usr/local/etc/sudoers.d/99local
Defaults timestamp_timeout = 5
Defaults passprompt = "%u@%h SUDO PASSWORD: "
%wheel ALL=(ALL) ALL
EOF

if [ -n "${PROXY_SERVER}" ]; then
	cat <<EOF>> /usr/local/etc/sudoers.d/99local
Defaults env_keep += "http_proxy https_proxy ftp_proxy no_proxy"
EOF
fi

mkdir -p /root/tmp
mkdir -p /home/${DEFAULT_USER_NAME}/tmp
chown ${DEFAULT_USER_NAME}:${DEFAULT_USER_GROUP_NAME} /home/${DEFAULT_USER_NAME}/tmp

#
# Run optional body script.
#
load_script "$OPTIONAL_SCRIPT_BODY"



##########
# Second snapshot. Configuration customized now.
##########
zfs snapshot -r ${ZFSBOOT_POOL_NAME}/${ZFSBOOT_BEROOT_NAME}/${ZFSBOOT_BOOTFS_NAME}@install-01custom

#
# Swap on ZFS volume
#
if [ -n "${ZVOL_SWAP_SIZE}" -a "${ZVOL_SWAP_SIZE}" != "0" ]; then
	zfs create -V ${ZVOL_SWAP_SIZE} -o org.freebsd:swap=on -o checksum=off -o sync=disabled -o primarycache=none -o secondarycache=none -o com.sun:auto-snapshot=false ${ZFSBOOT_POOL_NAME}/swap
fi

#
# Basic packages
#
if [ "xen" = "$hv" ]; then
	PKG_LIST="${PKG_LIST} xe-guest-utilities"
fi

if [ -n "${PKG_LIST}" ]; then
	export ASSUME_ALWAYS_YES=yes
	pkg install ${PKG_LIST}
fi

#
# /usr/local/etc/pkg.conf
#
if [ -n "${PROXY_SERVER}" ]; then
	cat <<EOF>> /usr/local/etc/pkg.conf
PKG_ENV {
  HTTP_PROXY: "${PROXY_SERVER}",
  HTTPS_PROXY: "${PROXY_SERVER}",
  FTP_PROXY: "${PROXY_SERVER}"
}
EOF
fi

#
# Run optional post script.
#
load_script "$OPTIONAL_SCRIPT_POST"



##########
# Third snapshot. Basic packages are installed.
##########
zfs snapshot -r ${ZFSBOOT_POOL_NAME}/${ZFSBOOT_BEROOT_NAME}/${ZFSBOOT_BOOTFS_NAME}@install-02basicpkg

