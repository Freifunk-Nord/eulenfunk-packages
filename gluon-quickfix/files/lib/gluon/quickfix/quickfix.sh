#!/bin/sh

safety_exit() {
        echo safety checks failed, exiting with error code 2
        exit 2
}

now_reboot() {
        logger -s -t "gluon-quickfix" -p 5 "rebooting... reason: $@"
        # push log to server here (nyi)
        # only reboot if the router started less than 1 hour ago
        if [ "$(cat /proc/uptime | sed 's/\..*//g')" -gt "3600" ] ; then
          echo rebooting
          /sbin/reboot -f
         fi
        logger -s -t "gluon-quickfix" -p 5 "AprilApril! Nicht während der ersten 60 Minuten nach dem Boot!"
}


# if the router started less than 10 minutes ago, exit
[ "$(cat /proc/uptime | sed 's/\..*//g')" -gt "60" ] || safety_exit

# if autoupdater is running less than 60 minutes, exit. otherwise emergency-reboot
UPGRADESTARTED='/tmp/autoupdate.lock'
if [ -f $UPGRADESTARTED ] ; then
  UPDATEWAIT='60'
  MAXAGE=$(($(date +%s)-60*${UPDATEWAIT}))
  LOCKAGE=$(date -r /tmp/autoupdate.lock +%s)
  if [ "$MAXAGE" -gt "$LOCKAGE" ] ; then
    now_reboot "stale autoupdate.lock file"
   fi
  safety_exit
 fi

echo safety checks done, continuing...

# reboot if there was a kernel (batman) error
# for an example gluon issue #680
dmesg | grep "Kernel bug" >/dev/null && now_reboot "gluon issue #680"

#zu viele Tunneldigger
[ "$(ps |grep -e tunneldigger\ restart -e tunneldigger-watchdog|wc -l)" -ge "2" ] && now_reboot "zu viele Tunneldigger-Restarts"

pgrep respondd >/dev/null || now_reboot "respondd not running"
pgrep dropbear >/dev/null || now_reboot "dropbear not running"


if [ "$(uci get wireless.radio0)" == "wifi-device" ] && [ ! "$(uci show|grep wireless.radio0.disabled|cut -d= -f2|tr -d \')" == "1" ] ; then
  echo has wifi enabled
  # check for hanging iw
  [ -f /tmp/iwdev.log ] && rm /tmp/iwdev.log
  iw dev>/tmp/iwdev.log &
  sleep 20
  [ $(cat /tmp/iwdev.log|wc -l) -eq 0 ] && now_reboot "iw dev freezes"
 fi




DEV="$(iw dev|grep Interface|grep -e 'mesh0' -e 'ibss0'| awk '{ print $2 }'|head -1)"

scan() {
        logger -s -t "gluon-quickfix" -p 5 "neighbour lost, running iw scan"
        iw dev $DEV scan lowpri passive>/dev/null
}

OLD_NEIGHBOURS=$(cat /tmp/mesh_neighbours 2>/dev/null)
NEIGHBOURS=$(iw dev $DEV station dump | grep -e "^Station " | awk '{ print $2 }')
echo $NEIGHBOURS > /tmp/mesh_neighbours

# check if we have lost any neighbours
for NEIGHBOUR in $OLD_NEIGHBOURS
do
        echo $NEIGHBOURS | grep $NEIGHBOUR >/dev/null || (scan; break)
done

