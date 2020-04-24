# Routing at the Host with Juniper's cRPD
Code authors: Christian Graf(cgraf@juniper.net) and David de Andres(ddeandres@juniper.net)

The cRPD can be instantiated in two modes. Either in host mode or networking mode. While in HOST mode only one instance of cRPD should be running to avoid unpredictable and erratic behavior. On the contrary, there is no theoretical limit on the number of cRPD instances that can run simultaneously. To be said is also that one instance in Host mode can co-exist with multiple other instances running on networking mode.

## Host mode
In this mode, any interface route from linux kernel gets distributed via netlink to the cRPD instance running in host networking mode. There is no need to configure any addresses within cRPD-CLI (except family ISO). Any IPv4/IPv6 addressing is derived from the host's kernel. In other words, all the host's default namespace will be exposed to the cRPD but will not be configured by it.

To run cRPD in host mode:
``` bash
#create volumes
docker volume create crpd01_config
docker volume create crpd01_varlog
#run cRPD in host mode --net=host
docker run --rm --detach --name crpd01 -h crpd01 --privileged --net=host -v crpd01_config:/config -v crpd01_varlog:/var/log -it crpd:19.4R1.10

```
To stop the cRPD:

```bash
docker stop crpd01
```

## Network mode
In this mode, a container, from now on referred to as VNF, will have a cRPD instance present in it's same namespace. This co-existence, allows the cRPD to manage the RIB and FIB belonging the namespace.
If no interface is moved to the namespace of the VNF, the cRPD will have no interfaces.
It is a design choice whether to move physical(and/or logical) or virtual interfaces (veth pairs).

To run cRPD in network mode:
```bash
# in this example, alpine (lightweight linux) is used as VNF
docker run --rm --detach --name alpine -h alpine --privileged --net=none -it alpine:latest
docker run --rm --detach --name crpd_alpine --privileged --net=container:alpine -v crpd01_config:/config -v crpd01_varlog:/var/log -it crpd:19.4R1.10
```
It is important to notice that in this mode, the VNF must be instantiated with *--net=none*
### Full example
As more complete example, below, a bridge is created where a physical(logical) interface and a veth endpoint are connected. The other endpoint of the veth interface is moved to the VNF's namespace
```bash
#start the containers
docker run --rm --detach --name alpine -h alpine --privileged --net=none -it alpine:latest
docker run --rm --detach --name crpd_alpine --privileged --net=container:alpine -v crpd01_config:/config -v crpd01_varlog:/var/log -it crpd:19.4R1.10
```
Find the VNF's pid to manipulate the namespace and define variables
```bash

pid=$(docker inspect alpine --format '{{ .State.Pid }}')
interface=##provide interface name
veth_main=veth_${pid}
veth_instance=vethi_${pid}
renamed_interface_in_instance=  ## could be set to: =${interface}

```
Cofigure both default and namespace network
```bash
# bring interface up, enable promisc mode
ip link set $interface promisc on
ethtool -K $interface gro off
ip link set $interface up

# create veth pair i
echo ${veth_main}
echo ${veth_instance}
sudo ip link add ${veth_main}  type veth peer name ${veth_instance}  # create veth pair

# create bridge. move veth_main to this bridge
bridge=alpine
brctl addbr $bridge # create bridge with name of docker_instance
ip link set $bridge up  # enable the bridge
brctl addif $bridge ${veth_main} # move veth_main to bridge
brctl addif $bridge ${interface} # move physical interface to bridge
ip link set ${veth_main} up # bring interface up


# link the namespace
sudo mkdir -p /var/run/netns
sudo ln -sf /proc/$pid/ns/net /var/run/netns/$pid

# move the instance-leg to crpd namespace
ip link set ${veth_instance} netns $pid
# bring interface up
ip netns exec $pid ip link set ${veth_instance} up

# configure ip address
sudo ip netns exec $pid ip addr add $ipadr dev ${veth_instance}
```

## Scripts and usage
Scripts for initialization of VNF's with attached cRPD have been created. In addition, cleanup scripts for removing the configuration are also provided
### run_vnf_and_crpd.sh
This scripts instantiates a vnf with an attached crpd connected to a physical interface though a bridge
```
useage: run_vnf_and_crpd.sh -i <interface_name> --vnf <vnf_name:tag> -c <crpd:tag> -a <ipadr> [OPTIONAL] -v (override volumes, minimum provide 2) <volume_name>:<mounting_point>
```
### destroy_vnf_and_crpd.sh
This scripts instantiates a vnf with an attached crpd connected to a physical interface though a bridge
```
useage: destroy_vnf_and_crpd.sh -i <interface_name> --vnf <vnf_name> [OPTIONAL] -v (delete volumes)>
```

### create_crpd_veths.sh
This script creates the networking configuration for  vnf and crpd containers already instantiated.
```
useage: create_crpd_veths.sh <docker_instance> <interface> <ip>
```
