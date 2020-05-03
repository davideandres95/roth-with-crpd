#!/bin/bash

# check if root
if [[ $EUID -ne 0 ]];
   then
	echo "This script must be run as root" 1>&2
	exit
fi

# check if arg is provided
if [ "$#" -ne 3 ];
    then
	echo "useage: $0 <docker_instance> <interface> <ip>"
	exit
fi
NAME=$1
interface=$2
ipadr=$3
pid=$(docker inspect $NAME --format '{{ .State.Pid }}') # get pid of docker-instance
echo "PID of docker $1: $pid"


# bring interface up, enable promisc mode
ip link set $interface promisc on
ethtool -K $interface gro off
ip link set $interface up

# link the namespace from the VNF/crpd to the :
mkdir -p /var/run/netns
ln -sf /proc/$pid/ns/net /var/run/netns/$NAME

# move the instance to crpd namespace
ip link set $interface netns $pid
ip netns exec $pid ip link set $interface up
ip netns exec $pid ip addr add $ipadr dev $interface
