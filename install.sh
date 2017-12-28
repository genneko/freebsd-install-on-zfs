#
# install.sh
#   FreeBSD ZFS custom installation script for use with bsdinstall.
#
# Usage
#   First, copy/create/edit *.cfg.sample to whatyoulike.cfg
#   on a host such as your laptop.
#   Optionally, do the same for *.scp files.
#
#     cp baremetal.cfg.sample whatyoulike.cfg
#     cp base.scp.sample base.scp
#     cp pkg.scp.sample pkg.scp
#     vi whatyoulike.cfg
#     vi base.scp
#     vi pkg.scp
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
#     export NAMESERVER=192.168.10.1
#     cd /tmp
#     fetch http://192.168.10.120:8000/install.sh
#     fetch http://192.168.10.120:8000/whatyoulike.cfg
#     export CUSTOM_CONFIG_FILE=whatyoulike.cfg
#     bsdinstall script install.sh
#     less bsdinstall_log
#     reboot
#
#   Full descriptions are found on the following URL.
#     https://github.com/genneko/freebsd-install-on-zfs
#

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
		fetch --no-proxy=* ${CUSTOM_CONFIG_BASEURL}/${filename}
		. ./${filename}
	fi
}

#
# void load_file <filename> <destpath>
#
load_file(){
	local filename="$1"
	local destpath="$2"
	if [ -n "$filename" -a -n "$destpath" ]; then
		if [ -e "$destpath" ]; then
			if [ ! -e "$destpath.dist" ]; then
				bkpath="$destpath.dist"
			else
				bkpath="$destpath.$(date '+%s')"
			fi
			mv "$destpath" "$bkpath"
		fi
		fetch --no-proxy=* -o "$destpath" ${CUSTOM_CONFIG_BASEURL}/${filename}
		if [ $? != 0 -a ! -e "$destpath" -a -e "$bkpath" ]; then
			mv "$bkpath" "$destpath"
		fi
	fi
}

_write_file(){
	local flag="$1"
	local destpath="$2"
	local content="$3"
	if [ -n "$destpath" ]; then
		IFS_SAVE=$IFS
		IFS=
		if echo "$flag" | fgrep -q "insertnewline"; then
			echo >> "$destpath"
		fi
		if echo "$flag" | fgrep -q "overwrite"; then
			if [ -e "$destpath" ]; then
				if [ ! -e "$destpath.dist" ]; then
					bkpath="$destpath.dist"
				else
					bkpath="$destpath.$(date '+%s')"
				fi
				mv "$destpath" "$bkpath"
			fi
			echo $content > "$destpath"
		else
			echo $content >> "$destpath"
		fi
		IFS=$IFS_SAVE
	fi
}

#
# void write_file <destpath> <content>
#
write_file(){
	_write_file "" "$1" "$2"
}
# insert newline first
write_file_nl(){
	_write_file "insertnewline" "$1" "$2"
}
# overwrite
write_file_new(){
	_write_file "overwrite" "$1" "$2"
}

#
# Shorthands (PART1)
#
cf_rc=/etc/rc.conf
cf_sysctl=/etc/sysctl.conf
cf_loader=/boot/loader.conf
cf_resolv=/etc/resolv.conf
cf_sshd=/etc/ssh/sshd_config

#
# Create temporary /etc/resolv.conf for name resolution.
#
if [ -n "$NAMESERVER" ]; then
	write_file_nl $cf_resolv "nameserver $NAMESERVER"
fi

#
# Load default configuration file.
#
load_script "${CUSTOM_CONFIG_FILE}"

: ${HOSTNAME:=freebsd}
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
: ${DEFAULT_USER_FULLNAME:=User &}
: ${DEFAULT_USER_ID:=500}
: ${DEFAULT_USER_PASSWORD:=freebsd}
: ${PKG_LIST=beadm sudo zfstools}
: ${ZVOL_SWAP_SIZE:=2G}

: ${KEYMAP=}
: ${TIME_ZONE=}
: ${PROXY_SERVER=}
: ${NO_PROXY=}
: ${SSH_PERMIT_ROOT_LOGIN_IPRANGE=}
: ${SSH_AUTHORIZED_KEYS_FILE=}
: ${OPTIONAL_SCRIPT_INIT=}
: ${OPTIONAL_SCRIPT_BASE=}
: ${OPTIONAL_SCRIPT_PKG=}

export HOSTNAME
export NIC_LIST
export IP_LIST
export NETMASK_LIST
export DEFAULTROUTER
export SEARCHDOMAINS
export NAMESERVER_LIST
export DEFAULT_ROOT_PASSWORD
export DEFAULT_USER_GROUP_NAME
export DEFAULT_USER_GROUP_ID
export DEFAULT_USER_NAME
export DEFAULT_USER_FULLNAME
export DEFAULT_USER_ID
export DEFAULT_USER_PASSWORD
export PKG_LIST
export ZVOL_SWAP_SIZE

export KEYMAP
export TIME_ZONE
export PROXY_SERVER
export NO_PROXY
export SSH_PERMIT_ROOT_LOGIN_IPRANGE
export SSH_AUTHORIZED_KEYS_FILE
export OPTIONAL_SCRIPT_INIT
export OPTIONAL_SCRIPT_BASE
export OPTIONAL_SCRIPT_PKG

#
# Shorthands (PART2)
#
username=$DEFAULT_USER_NAME
groupname=$DEFAULT_USER_GROUP_NAME
dir_user_home=/home/$username
dir_user_ssh=$dir_user_home/.ssh
dir_root_home=/root
dir_root_ssh=$dir_root_home/.ssh

cf_user_cshrc=$dir_user_home/.cshrc
cf_root_cshrc=$dir_root_home/.cshrc
cf_user_ssh_ak=$dir_user_ssh/authorized_keys
cf_root_ssh_ak=$dir_root_ssh/authorized_keys

tmp_cshrc=/cshrc.addon


#
# SNAPSHOT 00: (A) BASE SYSTEM INSTALLED.
#
zfs snapshot -r ${ZFSBOOT_POOL_NAME}/${ZFSBOOT_BEROOT_NAME}/${ZFSBOOT_BOOTFS_NAME}@install-00A-basesys-installed


#
# SCRIPT 00: ADDITIONAL INITIALIZATIONS via "init" script.
#
if [ -n "$OPTIONAL_SCRIPT_INIT" ]; then
	load_script "$OPTIONAL_SCRIPT_INIT"

	#
	# SNAPSHOT 00: (B) INIT SCRIPT EXECUTED.
	#
	zfs snapshot -r ${ZFSBOOT_POOL_NAME}/${ZFSBOOT_BEROOT_NAME}/${ZFSBOOT_BOOTFS_NAME}@install-00B-script-init-done
fi


##############################################################
# PART 01 of 02: BASIC SYSTEM CONFIGURATIONS
##############################################################
#
# Is this on a virtual environment (hypervisor)?
#
hv=$(sysctl -n kern.vm_guest)

#
# /etc/sysctl.conf
#
if [ -n "$hv" ]; then
	sysrc -f $cf_sysctl net.inet.tcp.tso=0
fi

#
# /boot/loader.conf
#
sysrc -f $cf_loader beastie_disable="NO"
sysrc -f $cf_loader autoboot_delay="3"

if [ -n "$hv" ]; then
	if [ "xen" = "$hv" ]; then
		sysrc -f $cf_loader console="vidconsole,comconsole"
	else
		sysrc -f $cf_loader console="vidconsole"
	fi
fi

#
# /etc/rc.conf
#
sysrc zfs_enable="YES"
sysrc hostname="${HOSTNAME}"
hostname $HOSTNAME
if [ -n "$KEYMAP" ]; then
	sysrc keymap="${KEYMAP}"
fi
sysrc defaultrouter="${DEFAULTROUTER}"
sysrc sshd_enable="YES"
sysrc dumpdev="NO"
sysrc ntpd_enable="YES"
sysrc ntpd_sync_on_start="YES"

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
	if [ $i -eq 1 ]; then
		export NIC1=$nic
	elif [ $i -eq 2]; then
		export NIC2=$nic
	fi
	i=`expr "$i" + 1`
done

#
# /etc/resolv.conf
#
write_file_new $cf_resolv "search ${SEARCHDOMAINS}"

for nameserver in $NAMESERVER_LIST; do
	write_file $cf_resolv "nameserver ${nameserver}"
done

#
# Timezone
#
if [ -n "$TIME_ZONE" ]; then
	cp /usr/share/zoneinfo/${TIME_ZONE} /etc/localtime
fi

#
# ZFS Pool's root dataset has no need to be mounted.
#
zfs set mountpoint=none ${ZFSBOOT_POOL_NAME}

#
# User configurations
#
echo ${DEFAULT_ROOT_PASSWORD} | pw usermod root -h 0 -s /bin/tcsh
pw groupadd -n ${DEFAULT_USER_GROUP_NAME} -g ${DEFAULT_USER_GROUP_ID}
echo ${DEFAULT_USER_PASSWORD} | pw useradd -n ${DEFAULT_USER_NAME} -c "${DEFAULT_USER_FULLNAME}" -u ${DEFAULT_USER_ID} -g ${DEFAULT_USER_GROUP_NAME} -G wheel -h 0 -m -s /bin/tcsh

#
# /etc/ssh/sshd_config
#

# SSH public keys
if [ -n "$SSH_AUTHORIZED_KEYS_FILE" ]; then
	mkdir $dir_user_ssh
	chown $username:$groupname $dir_user_ssh
	chmod 700 $dir_user_ssh
	load_file "$SSH_AUTHORIZED_KEYS_FILE" $cf_user_ssh_ak
	chown $username:$groupname $cf_user_ssh_ak
	chmod 600 $cf_user_ssh_ak

	if [ -n "${SSH_PERMIT_ROOT_LOGIN_IPRANGE}" ]; then
		mkdir $dir_root_ssh
		chmod 700 $dir_root_ssh
		load_file "$SSH_AUTHORIZED_KEYS_FILE" $cf_root_ssh_ak
		chmod 600 $cf_root_ssh_ak
	fi

	write_file $cf_sshd "ChallengeResponseAuthentication no"
fi

# SSH General configurations
if [ -n "${SSH_PERMIT_ROOT_LOGIN_IPRANGE}" ]; then
	cat <<-EOF>> $cf_sshd

		AllowUsers root $DEFAULT_USER_NAME

		Match Address ${SSH_PERMIT_ROOT_LOGIN_IPRANGE}
		  PermitRootLogin yes
	EOF
else
	write_file $cf_sshd "AllowUsers $DEFAULT_USER_NAME"
fi


#
# Shell configuration
#
cat <<-EOF> $tmp_cshrc

alias rm rm -i
alias mv mv -i
alias cp cp -i
alias ls ls -Fw

set noclobber
set ignoreeof
EOF

if [ -n "${PROXY_SERVER}" ]; then
	cat <<-EOF>> $tmp_cshrc

		setenv http_proxy ${PROXY_SERVER}
		setenv https_proxy ${PROXY_SERVER}
		setenv ftp_proxy ${PROXY_SERVER}
	EOF
	if [ -n "${NO_PROXY}" ]; then
		cat <<-EOF>> $tmp_cshrc
			setenv no_proxy "${NO_PROXY}"
		EOF
	fi

	export http_proxy=${PROXY_SERVER}
	export https_proxy=${PROXY_SERVER}
	export ftp_proxy=${PROXY_SERVER}

	if [ -n "${NO_PROXY}" ]; then
		export no_proxy="${NO_PROXY}"
	fi
fi

cat $tmp_cshrc >> $cf_root_cshrc
cat $tmp_cshrc >> $cf_user_cshrc
rm $tmp_cshrc

#
# crontabs
#
if [ ! -d /etc/cron.d ]; then
	mkdir -p /etc/cron.d
fi
cat <<-'EOF'> /etc/cron.d/00zfstools
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
# User temporary directories
#
mkdir -p $dir_root_home/tmp
mkdir -p $dir_user_home/tmp
chown $username:$groupname $dir_user_home/tmp

#
# Swap on ZFS volume
#
if [ -n "${ZVOL_SWAP_SIZE}" -a "${ZVOL_SWAP_SIZE}" != "0" ]; then
	zfs create -V ${ZVOL_SWAP_SIZE} -o org.freebsd:swap=on -o checksum=off -o sync=disabled -o primarycache=none -o secondarycache=none -o com.sun:auto-snapshot=false ${ZFSBOOT_POOL_NAME}/swap
fi

#
# SNAPSHOT 01: (A) BASE SYSTEM CONFIGURATIONS DONE.
#
zfs snapshot -r ${ZFSBOOT_POOL_NAME}/${ZFSBOOT_BEROOT_NAME}/${ZFSBOOT_BOOTFS_NAME}@install-01A-basesys-configured


#
# SCRIPT 01: ADDITIONAL BASE-SYSTEM CONFIGURATIONS via "base" script.
#
if [ -n "$OPTIONAL_SCRIPT_BASE" ]; then
	load_script "$OPTIONAL_SCRIPT_BASE"

	#
	# SNAPSHOT 01: (B) BASE SCRIPT EXECUTED.
	#
	zfs snapshot -r ${ZFSBOOT_POOL_NAME}/${ZFSBOOT_BEROOT_NAME}/${ZFSBOOT_BOOTFS_NAME}@install-01B-script-base-done
fi


##############################################################
# PART 02 of 02: BASIC PACKAGE INSTALLATION
##############################################################
if [ "xen" = "$hv" ]; then
	PKG_LIST="${PKG_LIST} xe-guest-utilities"
	sysrc xenguest_enable="YES"
	sysrc xe_daemon_enable="YES"
fi

if [ -n "${PKG_LIST}" ]; then
	export ASSUME_ALWAYS_YES=yes
	pkg install ${PKG_LIST}
fi

#
# SNAPSHOT 02: (A) BASIC PACKAGES INSTALLED.
#
zfs snapshot -r ${ZFSBOOT_POOL_NAME}/${ZFSBOOT_BEROOT_NAME}/${ZFSBOOT_BOOTFS_NAME}@install-02A-basicpkg-installed

#
# SCRIPT 02: ADDITIONAL PACKAGE CONFIGURATIONS via "pkg" script.
#
if [ -n "$OPTIONAL_SCRIPT_PKG" ]; then
	load_script "$OPTIONAL_SCRIPT_PKG"

	#
	# SNAPSHOT 02: (B) PKG SCRIPT EXECUTED.
	#
	zfs snapshot -r ${ZFSBOOT_POOL_NAME}/${ZFSBOOT_BEROOT_NAME}/${ZFSBOOT_BOOTFS_NAME}@install-02B-script-pkg-done
fi


#
# SNAPSHOT 03: (Z) INSTALLATION COMPLETE.
#
zfs snapshot -r ${ZFSBOOT_POOL_NAME}/${ZFSBOOT_BEROOT_NAME}/${ZFSBOOT_BOOTFS_NAME}@install-03Z-complete

