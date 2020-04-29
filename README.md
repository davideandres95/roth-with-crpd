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

- cRPD routing-daemon assigned to the Host (where finally all VNF's benefit from)
- cRPD attached to an specific VNF into an isolated namespace and move interfaces to it
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
[To-Do] Explain loopback interface naming convention for the different platforms

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
Which will produce the below output if we run `show interfaces routing`:
```
lab@ubuntu-cg ~> docker exec -it crpd_alpine cli
root@alpine> show interfaces routing
Interface        State Addresses
lsi              Up    MPLS  enabled
                       ISO   enabled
                       INET6 fe80::5068:27ff:fec4:9267
vethi_53408      Up    MPLS  enabled
                       ISO   enabled
                       INET6 fe80::9cae:91ff:fefb:d5a1
lo.0             Up    MPLS  enabled
                       ISO   enabled
                       INET  192.168.53.14
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
This use case covers KVM-based Virtual Machines with full-blown OS and its own routing-stack. The strength of this use case resides on their possibility to make use of more performant interfaces such as SR-IOV enabled ones. It is important to remark that for this use case, the cRPD runs on HOST mode as KVM enables a full OS.

The interesting part of this use cases resides in having 2 interfaces as we can use them to demonstrate uplink redundancy (ECMP). Thanks to this, for example, it can be shown that a running ping will not undergo packet loss even if the used link turns down as all the traffic will be inmediately shifted to the other interface.

For more information about KVM please refer to the [official page](https://www.linux-kvm.org/page/Main_Page).

[To-Do] Describe the topology here used

To launch a KVM guest:
```bash
virt-install --connect qemu:///system --virt-type kvm --name $name --ram $memory  --vcpus=$core --os-type linux --os-variant ubuntu16.04 --disk path=$image,format=qcow2 --disk cidata.iso,device=cdrom --
import --network network=default –noautoconsole
```
[To-Do] explain steps for increasing diskpspace and cloudinit
To verify that the KVM guest is running we make use of the (virsh tool)[https://libvirt.org/manpages/virsh.html#description]:
```bash
$ virsh list
Id    Name                           State
----------------------------------------------------
2     ubuntu_server_guest            running
```
To prepare the interfaces on the host for SR-IOV with 8 VF, a (reboot non-persistent) option is to perform:
```bash
$ echo 8 | sudo tee -a  /sys/class/net/<interface1>/device/sriov_numvfs
$ echo 8 | sudo tee -a  /sys/class/net/<interface2>/device/sriov_numvfs
```
A possibility to make this persistent is to include it in the `.bashrc` or configure it on `GRUB`. **Note**: to modify the number of VF an interim step to 0 is required.
To verify that SR-IOV is enabled:
```bash
$ ls -l /sys/class/net/<interface1>/device/virtfn* | grep fn7
lrwxrwxrwx 1 root root 0 Apr 23 12:14 /sys/class/net/ens8f0/device/virtfn7 -> ../0000:85:11.6
$ ls -l /sys/class/net/<interface2>/device/virtfn* | grep fn7
lrwxrwxrwx 1 root root 0 Apr 23 12:14 /sys/class/net/ens8f0/device/virtfn7 -> ../0000:85:11.7
```
The above `../0000:85:11.6` is really important and will be used in the next step to add the VF towards the guest. To do this, a convinient virsh xml file is created:

```xml
<!-------interface1----->
<interface type='hostdev' managed='yes'>
   <mac address="02:06:0A:81:11:6" />
   <source>
     <address domain="0x0000"  bus="0x85" slot="0x11" function="0x6" type="pci" />
   </source>
 </interface>

<!-------interface2----->
<interface type='hostdev' managed='yes'>
   <mac address="02:06:0A:81:11:7" />
   <source>
     <address domain="0x0000"  bus="0x85" slot="0x11" function="0x7" type="pci" />
   </source>
 </interface
```

[TO-DO] check if  `<target dev='ens9'/>` sets the name on the host

We can observe that the different parts of the output correspond to the domain, bus, slot and function which will enable virsh to connect it to the guest. Each interface is also provided with a unique MAC address. So at this point, the guest has an interface which must be configured:

```bash
sudo ifconfig <interface1> up
sudo ifconfig <interface2> up
sudo ip link add link <interface1> name <interface1>.<logical_unit> type vlan id <logical_unit>
sudo ip link add link <interface2> name <interface2>.<logical_unit> type vlan id <logical_unit>
sudo ip link set dev <interface1>.<logical_unit> up
sudo ip link set dev <interface2>.<logical_unit> up
sudo ip addr add 192.168.203.10/30 dev <interface1>.<logical_unit>
sudo ip addr add 192.168.200.10/30 dev <interface2>.<logical_unit>
sudo ip addr add 192.168.53.3 dev lo # for this demo a lo address is required
```

At this point, if we launch the cRPD container on HOST mode (as explained in the above section), all the interfaces should be known to him:
```
root@crpd01> show interfaces routing
Interface        State Addresses
...
lo.0             Up    MPLS  enabled
                       ISO   enabled
                       INET  192.168.53.3
ens9.143         Up    MPLS  enabled                <-- <interface1>.<logical_unit>
                       ISO   enabled
                       INET  192.168.203.10
                       INET6 fe80::6:aff:fe81:1106
ens9             Up    MPLS  enabled                <-- <interface1>
                       ISO   enabled
                       INET6 fe80::6:aff:fe81:1106
ens10            Up    MPLS  enabled                <-- <interface2>
                       ISO   enabled
                       INET  192.168.122.156
                       INET6 fe80::5054:ff:fec4:901c
ens10.143        Up    MPLS  enabled                <-- <interface2>.<logical_unit>
                       ISO   enabled
                       INET  192.168.200.10
                       INET6 fe80::6:aff:fe81:1107
```
In the same way, if we run `ip a` on the host we can see:
```bash
ubuntu@kvm_guest_bionic:~$ ip a
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN group default qlen 1000
    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
    inet 127.0.0.1/8 scope host lo
       valid_lft forever preferred_lft forever
    inet 192.168.53.3/32 scope global lo
       valid_lft forever preferred_lft forever
    inet6 ::1/128 scope host
       valid_lft forever preferred_lft forever
2: ens9: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc mq state UP group default qlen 1000
    link/ether 02:06:0a:81:11:06 brd ff:ff:ff:ff:ff:ff
    inet6 fe80::6:aff:fe81:1106/64 scope link
       valid_lft forever preferred_lft forever
2: ens10: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc mq state UP group default qlen 1000
    link/ether 02:06:0a:81:11:07 brd ff:ff:ff:ff:ff:ff
    inet6 fe80::6:aff:fe81:1107/64 scope link
       valid_lft forever preferred_lft forever
3: ens9.143@ens9: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue state UP group default qlen 1000
    link/ether 02:06:0a:81:11:06 brd ff:ff:ff:ff:ff:ff
    inet 192.168.203.10/30 scope global ens9.143
       valid_lft forever preferred_lft forever
    inet6 fe80::6:aff:fe81:1106/64 scope link
       valid_lft forever preferred_lft forever
4: ens10.143@ens10: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue state UP group default qlen 1000
    link/ether 02:06:0a:81:11:07 brd ff:ff:ff:ff:ff:ff
    inet 192.168.200.10/30 scope global ens10.143
       valid_lft forever preferred_lft forever
    inet6 fe80::6:aff:fe81:1107/64 scope link
       valid_lft forever preferred_lft forever
```
To configure the cRPD for ECMP:
```
## Last changed: 2020-04-23 13:50:06 UTC
version 20191212.201431_builder.r1074901;
policy-options {
    policy-statement export-all {
        then accept;
    }
    policy-statement plb {
        then {
            load-balance per-packet;
        }
    }
}
routing-options {
    forwarding-table {
        export plb;
    }
    autonomous-system 65000;
}
protocols {
    bgp {
        group MX480 {
           family inet {
                unicast;
            }
            export export-all;
            peer-as 65001;
            multipath;
            bfd-liveness-detection {
                minimum-interval 300;
                multiplier 3;
            }
            neighbor 192.168.203.9;
            neighbor 192.168.200.9;
        }
    }
}
```


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
