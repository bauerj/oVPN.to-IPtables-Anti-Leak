#!/bin/bash
#
# IPTABLES BLOCK SCRIPT v0.0.6

EXTIF="eth0";
TUNIF="tun0";
OVPNDIR="/etc/openvpn";
LANRANGE="192.168.0.0/16"
ALLOWLAN="0";
IP4TABLES="/sbin/iptables";
IP6TABLES="/sbin/ip6tables";

IP4TABSSAVE="/sbin/iptables-save";
IP4TRESTORE="/sbin/iptables-restore";
IP4FILESAVE="/root/save.ip4tables.txt";

IP6TABSSAVE="/sbin/ip6tables-save";
IP6TRESTORE="/sbin/ip6tables-restore";
IP6FILESAVE="/root/save.ip6tables.txt";

DEBUGOUTPUT="0";

# SETUP: chmod +x iptables.sh 
# START: ./iptables.sh
# UNLOAD: ./iptables.sh unload

##############################

#Doing Backup from existing IPtables
$IP4TABSSAVE > $IP4FILESAVE && echo "Backuped ip4tables to $IP4FILESAVE";
$IP6TABSSAVE > $IP6FILESAVE && echo "Backuped ip6tables to $IP6FILESAVE";

if [ "$1" = "unload" ]; then
$IP4TABLES -F
$IP4TABLES -Z
$IP4TABLES -P INPUT ACCEPT
$IP4TABLES -P FORWARD ACCEPT
$IP4TABLES -P OUTPUT ACCEPT
$IP6TABLES -F
$IP6TABLES -Z
$IP6TABLES -P INPUT ACCEPT
$IP6TABLES -P FORWARD ACCEPT
$IP6TABLES -P OUTPUT ACCEPT
echo "Rules unloaded" && exit 0;
fi;



# Flush iptables
$IP4TABLES -F
$IP6TABLES -F
# Zero all packets and counters.
$IP4TABLES -Z
$IP6TABLES -Z
# Set POLICY DROP
$IP4TABLES -P INPUT DROP
$IP4TABLES -P FORWARD DROP
$IP4TABLES -P OUTPUT DROP
$IP6TABLES -P INPUT DROP
$IP6TABLES -P FORWARD DROP
$IP6TABLES -P OUTPUT DROP

# Allow related connections
$IP4TABLES -A INPUT -i $EXTIF -m state --state ESTABLISHED,RELATED -j ACCEPT
$IP4TABLES -A INPUT -i $TUNIF -m state --state ESTABLISHED,RELATED -j ACCEPT
$IP4TABLES -A OUTPUT -o $EXTIF -m state --state ESTABLISHED,RELATED -j ACCEPT

# Allow loopback interface to do anything
$IP4TABLES -A INPUT -i lo -j ACCEPT
$IP4TABLES -A OUTPUT -o lo -j ACCEPT

if [ $ALLOWLAN -eq "1" ]; then
# Allow LAN access
$IP4TABLES -A INPUT -i $EXTIF -s $LANRANGE -j ACCEPT 
$IP4TABLES -A OUTPUT -o $EXTIF -d $LANRANGE -j ACCEPT
fi;

# Allow OUT over tunIF
$IP4TABLES -A OUTPUT -o $TUNIF -p tcp -j ACCEPT;
$IP4TABLES -A OUTPUT -o $TUNIF -p udp -j ACCEPT;
$IP4TABLES -A OUTPUT -o $TUNIF -p icmp -j ACCEPT;

# ALLOW OUTPUT to oVPN-IPs over $EXTIF at VPN-Port with PROTO

OVPNCONFIGS=`ls $OVPNDIR/*.ovpn $OVPNDIR/*.conf`;
test $DEBUGOUTPUT -eq "1" && echo -e "DEBUG OVPNCONFIGS=\n$OVPNCONFIGS";

L=0;
while read CONFIGFILE; do 
 test $DEBUGOUTPUT -eq "1" && echo "$CONFIGFILE";
 REMOTE=`grep "remote\ " "$CONFIGFILE"`;
 test $DEBUGOUTPUT -eq "1" && echo "$REMOTE";
 getPROTO=`echo $REMOTE|cut -d" " -f4`;
 IPDATA=`echo $REMOTE|cut -d" " -f2`;
 IPPORT=`echo $REMOTE|cut -d" " -f3`;
 test $DEBUGOUTPUT -eq "1" && echo "DEBUG: wc -m `echo $getPROTO | wc -m`";
 if [ `echo $getPROTO | wc -m` -eq "4" ]&&([ $getPROTO = "udp" ]||[ $getPROTO = "tcp" ]||[ $getPROTO = "UDP" ]||[ $getPROTO = "TCP" ]); then
  PROTO=$getPROTO;
 else
  PROTO=`grep "proto\ " "$CONFIGFILE" | cut -d" " -f2`;
 fi;
 test $DEBUGOUTPUT -eq "1" && echo "$IPDATA $IPPORT $PROTO";
 $IP4TABLES -A OUTPUT -o $EXTIF -d $IPDATA -p $PROTO --dport $IPPORT -j ACCEPT;
 L=$(expr $L + 1);
done < <(echo "$OVPNCONFIGS");

if [ $L -gt "0" ]; then
 echo "LOADED $L IPs TO TRUSTED IP-POOL";
else
 echo "ERROR: COULD NOT LOAD IPs FROM CONFIGS. RESTORING FROM BACKUP";
 $IP4TRESTORE $IP4TABSSAVE && echo "FAILED: reloaded from backup: $IP4FILESAVE";
 $IP6TRESTORE $IP6TABSSAVE && echo "FAILED: reloaded from backup: $IP6FILESAVE";
 exit 1
fi;

# STATUS
$IP4TABLES -nvL
$IP6TABLES -nvL
