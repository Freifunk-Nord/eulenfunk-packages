#!/bin/sh
# cc0, maintained by adorfer@nadeshda.org 

# wait 60 minutes if autoupdater is running
UPDATEWAIT='60'

safety_exit() {
  logger -s -t "gluon-quickfix" "safety checks failed $@, exiting with error code 2"
  exit 2
}

now_reboot() {
  # first parameter message
  # second optional -f to force reboot even if autoupdater is running
  MSG="rebooting... reason: $1"
  logger -s -t "gluon-quickfix" -p 5 $MSG
  if [ "$(sed 's/\..*//g' /proc/uptime)" -gt "3600" ] ; then
    LOG=/lib/gluon/quickfix/reboot.log
    # the first 5 times log the reason for a reboot in a file that is rebootsave
    [ "$(wc -l < $LOG)" -gt 5 ] || echo "$(date) $1" >> $LOG
    if [ "$2" != "-f" ] && [ -f /tmp/autoupdate.lock ] ; then
      safety_exit "autoupdate running"
    fi
    /sbin/reboot -f
  fi
  logger -s -t "gluon-quickfix" -p 5 "no reboot during first hour"
}

# don't do anything the first 10 minutes
[ "$(sed 's/\..*//g' /proc/uptime)" -gt "600" ] || safety_exit "uptime low!"

# check for stale autoupdater
if [ -f /tmp/autoupdate.lock ] ; then
  MAXAGE=$(($(date +%s)-60*${UPDATEWAIT}))
  LOCKAGE=$(date -r /tmp/autoupdate.lock +%s)
  if [ "$MAXAGE" -gt "$LOCKAGE" ] ; then
    now_reboot "stale autoupdate.lock file" -f
  fi
  safety_exit "autoupdate running"
fi

# batman-adv crash when removing interface in certain configurations
dmesg | grep -q "Kernel bug" && now_reboot "gluon issue #680"
# ath/ksoftirq-malloc-errors (upcoming oom scenario)
dmesg | grep "ath" | grep "alloc of size" | grep -q "failed" && now_reboot "ath0 malloc fail"
dmesg | grep "ksoftirqd" | grep -q "page allcocation failure" && now_reboot "kernel malloc fail"

# too many tunneldigger restarts
[ "$(ps |grep -c -e tunneldigger\ restart -e tunneldigger-watchdog)" -ge "9" ] && now_reboot "too many Tunneldigger-Restarts"

# br-client without ipv6 in prefix-range
brc6=$(ip -6 a s dev br-client | awk '/inet6/ { print $2 }'|cut -b1-9 |grep -c $(cat /lib/gluon/site.json|tr "," "\n"|grep \"prefix6\"|cut -d: -f2-3|cut -b2-10) 2>/dev/null)
if [ "$brc6" == "0" ]; then
  now_reboot "br-client without ipv6 in prefix-range (probably none)"
fi

reboot_when_not_running() {
  pgrep $1 || sleep 20 ; pgrep $1 || now_reboot "$1 not running"
}

# respondd or dropbear not running
reboot_when_not_running respondd
reboot_when_not_running dropbear

# check all radios for lost neighbours
for mesh_radio in `uci show wireless | grep -E -o '(ibss|mesh)_radio[0-9]+' | awk '!seen[$0]++'`; do
  radio="$(uci get wireless.$mesh_radio.device)"
  if [[ "$(uci -q get wireless.$radio.disabled)" != "1" && "$(uci -q get wireless.$mesh_radio.disabled)" != "1" ]]; then
    iw dev > /tmp/iwdev.log &
    p_iw=$!
    sleep 20
    kill -0 $p_iw 2>/dev/null && now_reboot "iw dev freezes or $radio misconfigured"

    DEV="$(uci get wireless.$mesh_radio.ifname)"
    scan() {
      logger -s -t "gluon-quickfix" -p 5 "neighbour lost, running iw scan"
      iw dev $DEV scan lowpri passive>/dev/null
    }

    OLD_NEIGHBOURS=$(cat "/tmp/mesh_neighbours_$mesh_radio" 2>/dev/null)
    NEIGHBOURS=$(iw dev $DEV station dump | grep -e "^Station " | cut -f 2 -d ' ')
    echo $NEIGHBOURS > "/tmp/mesh_neighbours_$mesh_radio"
    for NEIGHBOUR in $OLD_NEIGHBOURS; do
       echo $NEIGHBOURS | grep -q $NEIGHBOUR || (scan; break)
    done
  fi
done
