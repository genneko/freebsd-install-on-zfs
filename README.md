# freebsd-install-on-zfs
FreeBSD ZFS custom installation script for use with bsdinstall.

## Quick Start
Basically, you need two hosts which can commnicate each other. One is a host to which you install FreeBSD ("Target" here) and the other is a host which provides the first one with this install script ("Provider" here). The latter may be your laptop or anything like that.

### Provider (hosting scripts to Target)
1. Clone this repository on the Provider.
    ```
    provider$ cd ~/tmp
    provider$ git clone https://github.com/genneko/freebsd-install-on-zfs.git
    ```

2. Copy/rename sample \*.cfg/scp files and edit them as needed.

    See [Configuration parameters](#configuration-parameters) for details.
    ```
    provider$ cd freebsd-install-on-zfs
    provider$ cp baremetal.cfg.sample myserver.cfg
    provider$ cp body.scp.sample body.scp
    provider$ cp post.scp.sample post.scp
    provider$ vi myserver.cfg
    provider$ vi body.scp
    provider$ vi post.scp
    ```

3. Start a web server to host this repository contents, more specifically install.sh and \*.cfg/scp files. Off course, you can also put those files into your existing web server's document directory instead of newly starting a service.

    One way to do this is using the python's built-in web server module as follows.
    ```
    provider$ python -m SimpleHTTPServer
    Serving HTTP on 0.0.0.0 port 8000 ...
    ```

### Target (a host to install FreeBSD on)
1. Boot the Target with a FreeBSD installer.

2. Go into shell at the welcome dialog.

3. Do the basic network and other configurations.

    If you specify a domainname for CUSTOM_CONFIG_BASEURL in .cfg, you also have to set NAMESERVER to one of the available nameserver IP addresses and export it.
    ```
    # dhclient em0
    # cat /etc/resolv.conf
    nameserver 192.168.10.1
    # export NAMESERVER=192.168.10.1
    ```
    or
    ```
    # ifconfig vtnet0 inet 172.16.10.100 netmask 255.255.255.0
    # route add default 172.16.10.1
    # cat<<EOS>/tmp/bsdinstall_etc/resolv.conf
    > nameserver 172.16.10.5
    > nameserver 172.16.20.5
    > EOS
    # export NAMESERVER=172.16.10.5
    ```

4. Download install.sh and .cfg file from the Provider. Note that you don't have to download \*.scp files because they are automatically downloaded in the second phase of the installtion process.
    ```
    # cd /tmp
    # fetch http://target.example.com:8000/install.sh
    # fetch http://target.example.com:8000/myserver.cfg
    ```

5. Set the CUSTOM_CONFIG_FILE to .cfg filename and export it.
    ```
    # export CUSTOM_CONFIG_FILE=myserver.cfg
    ```

6. Run bsdinstall with the script.
    If you set ZFSBOOT_GELI_ENCRYPTION to 1, you will be asked a passphrase for GELI.
    ```
    # bsdinstall script install.sh
    ```

7. Check a log file generated by bsdinstall.
    ```
    # less bsdinstall_log
    ```

8. Reboot into the newly installed system.
    If you enabled GELI encryption, you will be asked a passphrase in the earliest stage of boot process.
    ```
    # shutdown -r now
    ```

9. After the first boot, login as a DEFAULT_USER_NAME and perform necessary configurations as usual. You can also automate some of those tasks by customizing post.scp.
    ```
    $ sudo passwd root
    $ passwd freebsd
    
    $ sudo zfs snapshot -r zroot/ROOT/default@install-03user
    $ sudo beadm create 11.1
    
    $ sudo freebsd-update fetch install
    
    $ sudo zfs snapshot -r zroot/ROOT/default@install-04up2p4
    ..
    ```

## Configuration parameters
### Variables used during system installation process (phase 1)
__Bold__ is mandatory while the others are optional.

- DISTRIBUTIONS

    System components to install such as base.txz, kernel.txz, src.txz, lib32.txz, ports.txz and doc.txz. List them using space as a delimiter. Default is "base.txz kernel.txz".

- __ZFSBOOT_DISKS__

    Space-delimited list of target disk(s) on which the OS is installed. You should set this appropriately to match your target system.

- __ZFSBOOT_VDEV_TYPE__

    How to bundle multiple disks (stripe, mirror, raid10, raidz1, raidz2 and raidz3). Specify 'stripe' for a single disk installation. Default is 'stripe' but you should check it anyway.
 
- ZFSBOOT_SWAP_SIZE

    Size of a dedicated swap partition. If you use ZVOL for swap, leave this at its default value and set the swap size in ZVOL_SWAP_SIZE instead. Default is 0.

- ZFSBOOT_GELI_ENCRYPTION

    Set this to non-empty value (e.g. 1) when you want to use whole disk encryption with GELI. Default is none (empty string).

- __ZFSBOOT_DATASETS__

    Specify a ZFS dataset layout.

### Variables used during post-installation setup process (phase 2)

- __CUSTOM_CONFIG_BASEURL__

    Web-accessible location of configuration file (.cfg) and optional post-installation scripts (.scp). They are automatically downloaded in the phase 2 (post-installation setup).

- OPTIONAL_SCRIPT_PRE

    Optional script which is executed at the very beginning of the phase 2. Default is none (empty string).

- OPTIONAL_SCRIPT_BODY

    Optional script which is executed at the middle of the phase 2. Default is none (empty string).

- OPTIONAL_SCRIPT_POST

    Optional script which is executed at the end of the phase 2 (thus the end of the installation). Default is none (empty string).

- __HOSTNAME__

    Target system's hostname. It can be FQDN.

- KEYMAP

    A keymap to use (e.g. jp).

- __NIC_LIST__

    Space-delimited list of network interface names.

- __IP_LIST__

    Space-delimited list of IP addresses. The order must match NIC_LIST.

- __NETMASK_LIST__

    Space-delimited list of netmasks. The order must match NIC_LIST.

- __DEFAULTROUTER__

    Default gateway (router) IP address.

- __SEARCHDOMAINS__

    Space-delimited list of domains used for name resolution.

- __NAMESERVER_LIST__

    Space-delimited list of name servers to use.

- TIME_ZONE

    A timezone to use (e.g. Asia/Tokyo).

- PROXY_SERVER

    Set this to something like ``http://proxyhost:port/`` if the target system has to use a HTTP proxy to reach outside world. Default is none (empty string).

- PKG_LIST

    Space-delimited list of FreeBSD's pkgng package names to install. Default is "beadm sudo zfstools".

- ZVOL_SWAP_SIZE

    Size of a ZVOL used for swap space. Default is 2G.
