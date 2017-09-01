# gluon-quickfix

This package will add a cronjob that fixes some problems that rarely occur, but are easy to work around. 

### Safety checks:
To be sure, that the script is not disturbing the start and update process:
- if autoupdater is running, `exit`
- if the router started less than 5 minutes ago, `exit`

### Workarounds
- check if we have lost any neighbours, `iw dev $DEV scan`
- if dropbear is not running, reboot (probably ram was full, so more services might've crashed)
- reboot if there was a kernel (batman) error

Manual installation
===================

If you don't have this package in your firmware, you can still install it
manually on a node:

```
ROUTER_IP='your:node::ip6'
LOGIN="root@[$ROUTER_IP]"
git clone https://github.com/Freifunk-Nord/eulenfunk-packages
cd eulenfunk-packages/
git checkout lede
cd gluon-quickfix/
scp -r files/* $LOGIN:/
ssh $ROUTER_IP "/etc/init.d/micrond reload;"
```

How is this implemented?
========================

There is only one bash file `/lib/gluon/quickfix/quickfix.sh` that is called by a cron job every
5 Minutes in `/usr/lib/micron.d/quickfix`. So, if you want to change the rhythm or disable it
just edit that micron.d-file.

The reboot function logs the reasons for the first 5 reboots in the file `/lib/gluon/quickfix/reboot.log`
so if that file exists, you should have a look there to find out, what problems occur here.

