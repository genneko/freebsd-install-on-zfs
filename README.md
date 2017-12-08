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
    
    $ sudo sysrc ntpd_enable=YES
    $ sudo sysrc ntpd_sync_on_start=YES
    $ sudo service ntpd start
    
    $ sudo zfs snapshot -r zroot/ROOT/default@install-03user
    $ sudo beadm create 11.1
    
    $ sudo freebsd-update fetch install
    
    $ sudo zfs snapshot -r zroot/ROOT/default@install-04up2p4
    ..
    ```

