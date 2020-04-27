# Routing at the Host with Juniper's cRPD
Code authors: Christian Graf(cgraf@juniper.net) and David de Andres(ddeandres@juniper.net)

## Pre-requisites
+ Ubuntu 16.04 baremetal or VM. Other distrubtions and versions might work too, though not verified
+ Docker Engine. E.g. by following the instructions [https://docs.docker.com/engine/install/ubuntu/](Install Doker Engine on Ubuntu)
+ Juniper cRPD. Download and import cRPD from the Juniper support downloads page. Currently using version 19.4R1.10.
+ Juniper cRPD license key (required to run BGP here)

## Table of contents
1. Introduction
2. Useful commands and information
   - Virtual ethernet pairs
3. Host Mode
   - Installing a crpd license
4. Networking mode
5. Use case descriptions
6. Scripts documentation
7. Known issues

## Introduction

cRPD is Juniper routing protocol stack decoupled from JUNOS and packaged for Linux container environments.
+ Deployable on demand as a microservice
+ Lightweight: 3 seconds startup, ~ 350 MB image size, ~ starting from 100MB RAM
+ 200M RIB, 48K routes/sec FIB download
+ Can program Linux FIB: IPv4, IPv6, MPLS
+ NETCONF, OpenConfig, CLI
+ Automation, Telemetry,  Programmability
+ Supports Kubernetes, Docker swarm

The cRPD can be instantiated in two modes. Either in host mode or networking mode. While in host mode only one instance of cRPD should be running to avoid unpredictable and erratic behavior. On the contrary, there is no limit on the number of cRPD instances that can run simultaneously in networking mode. To be said is also that one instance in host mode can co-exist with multiple other instances running on networking mode.

This guide is covering these usecases:

- assign the cRPD routing-daemon to the Host (where finally all VNF's benefit from)
- attach a cRPD to an specific VNF into an isolated namespace and move interfaces to it
- run cRPD in a KVM-based VM in host mode and with SR-IOV enabled interfaces
- [TO-DO] allow the creation of a demo-topology to develop and stage new network-designs 

## Useful comands and information

```bash
#Junos Commands for cRPD
> show interface routing # displays the interfaces present in the cRPD’s namespace
> show bgp summary # presents a summary of the bgp neighbors' status
> show  route protocol bgp # presents the routes learned trough bgp peers

#Host commands
docker stats # presents the cpu and memory consumption statistics per container
docker volume list # lists the current existing docker volumes
docker volume inspect <volume_name> # provides information about the volume.
docker load --input crpd.tar #loads a crpd image into docker

#Network Namespace management commands
ip netns show # lists the existing namespaces
ip netns exec <namespace> ip addr # lists the interfaces and ip addresses of the provided namespace
ip netns exec <namespace> <command> # runs any command inside the provided namespace
ip link set <interface> netns <namespace> # moves the interface into the specified namespace
#VNF commands
ip address # shows the interfaces and ip addresses  available in the vnf’s namespace
ip routes # Shows the ip routes known to this vnf container

```

### Virtual ethernet pairs (veth)
The veth devices are virtual Ethernet devices. They can act as tunnels between network namespaces to create a bridge to a physical network device in another namespace, but can also be used as standalone network devices.
Source and further information: [veth - Virtual Ethernet Device](http://man7.org/linux/man-pages/man4/veth.4.html)

## Host mode
In this mode, any interface route from linux kernel gets distributed via netlink to the cRPD instance running in host networking mode. There is no need to configure any addresses within cRPD-CLI (except family ISO). Any IPv4/IPv6 addressing is derived from the host's kernel. In other words, all the host's default namespace will be exposed to the cRPD but will not be configured by it.

To run cRPD in host mode:
``` bash
#create volumes
docker volume create <volume_for_config>
docker volume create <volume_for_varlog>
#run cRPD in host mode --net=host
docker run --rm --detach --name <name> -h <hostmode> --privileged --net=host -v <volume_for_config>:/config -v <volume_for_varlog>:/var/log -it crpd:19.4R1.10

```
To stop the cRPD:

```bash
docker stop crpd01
```
### Installing the license
If this is the first time you run cRPD in this testbed, you need to install the cRPD license key. There are several options, the easiest is to launch the cli via `docker exec -it crpd cli` and then copy-pasting the license code 'request system license add terminal'. Another option is to pre-provision it on the config volume that is provided when running the container. To find the mounting point run `docker volume ls` and then `docker volume inspect <vol_name>`, which will display the path where the volume files are. Last, copy the license file to the `./license` folder.

## Network mode
In this mode, a container, from now on referred to as VNF, will have a cRPD instance present in it's same namespace. This co-existence, allows the cRPD to manage the RIB and FIB belonging the namespace.
If no interface is moved to the namespace of the VNF, the cRPD will have no interfaces.
It is a design choice whether to move physical(and/or logical) or virtual interfaces (veth pairs).

To run cRPD in network mode:
```bash
# in this example, alpine (lightweight linux) is used as VNF
docker run --rm --detach --name alpine -h alpine --privileged --net=none -it alpine:latest
docker run --rm --detach --name crpd_alpine --privileged --net=container:alpine -v <volume_for_config>:/config -v <volume_for_varlog>:/var/log -it crpd:19.4R1.10
```
It is important to notice that in this mode, the VNF must be instantiated with *--net=none*

At this point, if we run `show interfaces routing` it won't display any interfaces because the namespace where it is running is empty. In the same way, if we log into the VNF and perform an `ip route` command, we won't see any routes.
```
root@alpine> show interfaces routing
Interface        State Addresses
lsi              Up    MPLS  enabled
                       ISO   enabled
                       INET6 fe80::5068:27ff:fec4:9267
lo.0             Up    MPLS  enabled
                       ISO   enabled

```
To add interfaces to the namespace:
```
ip link set <interface> netns <namespace>
```


## Use case description

### Attach cRPD to an specific VNF
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

### cRPD on KVM and SR-IOV 
[TO-DO]

### creation of a demo-topology
[TO-DO]

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

## Known Issues

1. IFL is not detected by cRPD on Networking mode
2. BFD repports an error 
