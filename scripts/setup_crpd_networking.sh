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
docker_instance=$1
interface=$2
ipadr=$3
pid=$(docker inspect $docker_instance --format '{{ .State.Pid }}') # get pid of docker-instance
veth_main=veth_${pid}
veth_instance=vethi_${pid}
renamed_interface_in_instance=${veth_instance}  ## could be set to: =${interface}
echo "PID of docker $1: $pid"


# bring interface up, enable promisc mode
ip link set $interface promisc on
ethtool -K $interface gro off
ip link set $interface up


# link the namespace
mkdir -p /var/run/netns
ln -sf /proc/$pid/ns/net /var/run/netns/$pid

# move the instance-leg to crpd namespace
ip link set $interface netns $pid
# optional - rename the veth-interface
#ip netns exec $pid ip link set dev ${veth_instance} name $renamed_interface_in_instance 
ip netns exec $pid ip link set $interface up

ip netns exec $pid ip addr add $ipadr dev $interface # configure ip address



