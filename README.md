# Routing at the Host (RotH) with Juniper's cRPD
Code authors: Christian Graf(cgraf@juniper.net) and David de Andres(ddeandres@juniper.net)

## Disclaimer
This repository is a best-effort work. This means that it can contain mistakes in the documentation as well as bugs in the scripts provided. Therefore, please use it at your own risk.
Feedback and questions welcome.

# Table of contents
1. Introduction and Use case Overview
   - General use cases for cRPD
   - Why RotH
   - RoTH deployment options
   - Covered use cases
2. Scenarios Overview
3. Pre-requisites
4. Setting up general stuff
5. Use case 1 - RotH - cRPD populates the hosts default RIB
   - config and setup
6. Use case 2 - cRPD providing routing-knowledge to another docker-container
   - config and setup
7. Use case 3 - cRPD on KVM and SR-IOV
   - config and setup
8. cRPD for testing and Lab infra
    - Custom Topologies creation
9. PCI-address mapping and CPU-Pinning
10. Kernel VRFs with cRPD

Appendix A. Scripts and usage
Appendix B. Known issues
Appendix C. Useful commands and information
## Introduction

cRPD is Juniper routing protocol stack decoupled from JUNOS and packaged for Linux container environments.
+ Deployable on demand as a microservice
+ Lightweight: 3 seconds startup, ~ 350 MB image size, ~ starting from 100MB RAM
+ 200M RIB, 48K routes/sec FIB download
+ Can program Linux FIB: IPv4, IPv6, MPLS
+ NETCONF, OpenConfig, CLI
+ Automation, Telemetry,  Programmability
+ Supports Kubernetes, Docker swarm
### Download
Juniper makes it easy for you to see how effective our containerized routing protocol daemon (cRPD) can be in your own environment. Simply download, install, and start using cRPD.
Start your [90 days free trial](https://www.juniper.net/us/en/dm/crpd-trial/) today.
### General use cases for cRPD
  - cRPD can be deployed as BGP Route-Reflector/Route-Server
  - cRPD might be used as Routing-Daemon on a Whitebox-switch or some custom hardware to built your own router
  - cRPD might be used for the "Routing on the Host (RotH)" purpose. This is what is covered in this doc.

### Why RotH

When looking at the RotH use case, the interested reader might ask for what good reason the cRPD might be beneficial?

First of all, when the Host acts as router, then there is no need to run VRRP, MC-LAG or Virtual-Chassis to provide link-redundancy towards the attached host. All VRRP, MC-lAG and Virtual-Chassis require a dependency between the involved switches/routers, which adds a burden for operations and increase e.g. troubleshooting-complexity with e.g. an insane state for MC-LAG (via ICCP-Protocol). In the worst case, then both switches running the MC-LAG might be affected, which somewhat nullifies the benefit of multihoming.
As an alternative option, plain routing on the host does not need any further syncing (e.g. arp-state syncing for MC-lag) between the switches, they just route.

Therefore, a solution would be to enable BGP-routing on the host via cRPD and VRRP, MC-LAG and Virtual-chassis could then be removed while the host would still have full redundant ECMP-capable uplinks.

Another aspect is effectively a reverse-perspective VRRP:
- to know if its various upstreams are alive.
- simply want a default-route, perhaps with load balancing.
- In some cases, have enough prefix data to provide for actual destination network failure detection

Simple BGP solves these problems quite nicely, especially if coupled with BFD. Providing more prefix-data can be solved by subscribing via policy to receive «important destination»" .

RoTH provides better ECMP-redundancy, while lowering complexity on the switches it is attached to.

### RoTH deployment options

- cRPD populating Hosts routing-table, where finally all VNF's can benefit from
- cRPD populating a specific docker-containers routing-table
- cRPD populating a KVM-guests routing-table
- [experimental]cRPD could be used to build a network-topology to develop new configurations, prepare for testing and even run scaling-tests
- the use cases of cRPD deployed on whitebox-switches is not covered in this doc


### Covered use cases

The cRPD is agnostic to the linux namespace it is launched in. This enables different scenarios depending on the underlying host's configuration. This guide is covering these use cases:


1. When launched in the hosts default namespace, then cRPD populates the hosts routing-table, thus providing routing-knoweldge to the native TCP-/IP stack. As result any applications/hypervisors running on the host (and finally VNF's) can make use the routing-knoweldge shared by cRPD. In addition cRPD can provide ECMP over existing redundant links.

2. It might be desired, that routing-knowledge shall only made available to specific docker-containers. In such use case the cRPD can be launched in the same network-namespace as the target docker-container.

3. Finally, cRPD can be tight to a KVM-guest. In such case the KVM-guest must be able to launch itself docker-containers to start the cRPD.

Please note, that there is no hard-limit on the cRPD instances which can be launched on the Host.
However, only one cRPD instance shall run in the default namespace as it will manage the default ip stack and having more than one could cause unstable behavior of the host.
But as already mentioned, you can launch any number of cRPD instances isolated in different namespaces where other containers might or might not be present.

## <a name="scenarios"></a>Scenarios overview
The below diagram maps with the above mentioned use cases. The configuration parameters displayed are the ones which have been used on our tests so please treat them as examples.
![](media/topology_diagram.png)
## Pre-requisites
+ Ubuntu 18.04
+ see: [Juniper cRPD official documentation](https://www.juniper.net/documentation/en_US/crpd/topics/reference/general/crr-system-requirement-docker.html)
+ Docker Engine. E.g. by following the instructions [Install Doker Engine on Ubuntu](https://docs.docker.com/engine/install/ubuntu/)
+ Juniper cRPD. Download and import cRPD from the Juniper support downloads page. Currently using version 19.4R1.10. cRPD can be downloaded for free over a [90 days trial](https://www.juniper.net/us/en/dm/crpd-trial/)
+ Juniper cRPD license key (required to run BGP here)

## Setting up general stuff

### Loading the cRPD image
Once the crpd.tgz file has been downloaded from juniper.net, it must be loaded into docker. To do this:
```bash
docker load --input crpd.tgz
```
It can now be verified that it is present with:
```bash
docker image ls
```
### Creating docker volumes
Volumes are the preferred mechanism for persisting data generated by and used by Docker containers. Volumes are often a better choice than persisting data in a container’s writable layer, because a volume does not increase the size of the containers using it, and the volume’s contents exist outside the lifecycle of a given container. For more info, [Docker-volumes](https://docs.docker.com/storage/volumes/).
To create a volume:
```bash
docker volume create <volume_name>
```
[TO-DO] pre-populating config-files
### Loopback interface across platforms
[TO-DO] explain the different naming conventions for the loopback address across crpd, host and junos.

### Installing the license
If this is the first time you run cRPD in this testbed, you need to install the cRPD license key. There are several options, the easiest is to launch the cli via `docker exec -it crpd cli` and then copy-pasting the license code 'request system license add terminal'. Another option is to pre-provision it on the config volume that is provided when running the container. To find the mounting point run `docker volume ls` and then `docker volume inspect <vol_name>`, which will display the path where the volume files are. Last, copy the license file to the `./license` folder. We must now load it in the cRPD
```
docker exec -it crpd cli
#in case it has been copied into the volume
request system license add /config/license/<filename>
#in case you want to copy paste it
request system license add terminal
```

## Use case 1 - RotH - cRPD populates the hosts default RIB
The cRPD can be used to use the native TCP/Ip stack of the host and polulate the hosts routing-table via any protocol running on the cRPD.
Technically the cRPD runs into the default-namespace of the Host, hence in the document we name it the "Host-Mode".

In Host-Mode, any interface route from linux kernel gets distributed via netlink to the cRPD instance. There is no need to configure any addresses within cRPD-CLI (except family ISO [TO-DO] check MPLS). Any IPv4/IPv6 addressing is derived from the host's kernel. In other words, all the host's default namespace will be exposed to the cRPD but will not be configured by it.

### Use case 1 - config and setup (Quickstart)
With this set-up, we will provide the host with redundant ECMP uplinks.
To run cRPD in host mode:
``` bash
#create volumes
docker volume create crpd_config
docker volume create crpd_varlog
#run cRPD in host mode --net=host
docker run --rm --detach --name crpd01 -h crpd01 --privileged --net=host -v crpd_config:/config -v crpd_varlog:/var/log -it crpd:default
```
To log into the cRPD cli:
```bash
docker exec -it crpd01 cli
```
Where crpd01 is the name of the container where you would like to run a command, cli is the command and -i stands for interactive and -t for tty.

The configuration for ECMP with BGP and BFD for the cRPD:
```
root@crpd01> show configuration
policy-options {
    policy-statement lo {
        term loopback {
            from interface lo.0;
            then accept;
        }
        term last {
            then reject;
        }
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
    router-id 192.168.53.2;
    autonomous-system 65002;
}
protocols {
    bgp {
        group to-mx {
            type external;
            family inet {
                unicast;
            }
            export lo;
            peer-as 65001;
            multipath;
            bfd-liveness-detection {
                minimum-interval 300;
                multiplier 3;
            }
            neighbor 192.168.200.5;
            neighbor 192.168.203.5;
        }
    }
}
```
The counterpart configuration on the neighbor(MX):
```
policy-options {
    policy-statement lo {
        term loopback {
            from interface lo0.0;
            then accept;
        }
        term last {
            then reject;
        }
    }
}
routing-options {
    autonomous-system 65001;
}
protocols {
    bgp {
        group to_crpd01 {
            type external;
            family inet {
                unicast;
            }
            export lo;
            peer-as 65002;
            bfd-liveness-detection {
                minimum-interval 300;
                multiplier 3;
            }
            neighbor 192.168.200.6;
            neighbor 192.168.203.6;
        }
    }
}
```
Finally, to stop the cRPD:

```bash
docker stop <name>
```

## Use case 2 - cRPD providing routing-knowedge to another docker-container only

In this mode it is desired to provide any other docker-container a dedicated routing-daemon.
As such in this document we name this use case "non-default namespace mode"

For below solution is it important to have in mind that docker-containers make extensive use on the namespaces the linux-kernel is offering. With a name-space, kernel-resources are partitioned and kept hidden from each other. As result, a docker-container can either run in the default network-namespace, or it can also run in its "own" namespace. If now a routing-daemon shall be attached to a docker-container, then there is just **one important step**:
- The cRPD as routing-daemon must run in the same namespace as the target docker-container.

When launching cRPD, this is achieved by setting the `-net=container<containername>` as seen in below example. Finally, the operator need to decide which interfaces shall be exposed towards the given network-namespace.

One, possible solution are from dockers default-networking, virtual-ethernet-pairs (veth) or even physical interfaces like ens8f0 or subunits ens8f0.142. All of them are possible and covered in this guide.

This co-existence of cRPD and the target docker-container running in same namespace, allows the cRPD to manage the RIB and FIB belonging the namespace.

To run cRPD in "non-default namespace mode"
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

Different kind of interfaces can be attached to cRPD and therefore can be moved to the required namespace:
- A physical interface (ifd) like ens8f0
- A logical interface (ifl) like ens8f0.142
- A virtual ethernet device (veth)

### Virtual ethernet pairs (veth)
The veth devices are virtual Ethernet devices. They can act as tunnels between network namespaces to create a bridge to a physical network device in another namespace, but can also be used as standalone network devices.
Source and further information: [veth - Virtual Ethernet Device](http://man7.org/linux/man-pages/man4/veth.4.html)

So coming back to how to add any interface to the namespace:
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

### Use case 2 - config and setup

As a more complete example, below, a logical interface is moved to the cRPD-VNF shared namespace.
```bash
#start the containers
docker run --rm --detach --name alpine -h alpine --privileged --net=none -it alpine:latest
docker run --rm --detach --name crpd_alpine --privileged --net=container:alpine -v crpd01_config:/config -v crpd01_varlog:/var/log -it crpd:19.4R1.10
```
To perform the networking setings:
```bash
#Find the VNF's pid to manipulate the namespace and define variables
pid=$(docker inspect alpine --format '{{ .State.Pid }}')
ns_name=crpd_alpine ##any useful name to identify the namespace can be used
# link the namespace
sudo mkdir -p /var/run/netns #in case the folder had never been created
sudo ln -sf /proc/$pid/ns/net /var/run/netns/$ns_name

#Create the logical interface and move it to the namespace
IFD=##provide the physical interface name e.g ens8f0
IFL=##provide the logical unit e.g 141
interface=$IFD.$IFL
sudo ip link set $IFD promisc on
sudo ethtool -K $IFD gro off
sudo ip link set $IFD up
sudo ip link add link $IFD name $interface type vlan id $IFL

# move the instance-leg to crpd namespace
sudo ip link set ${interface} netns $ns_name
# bring interface up
sudo ip -n $ns_name link set ${interface} up

# configure ip address
sudo ip -n $ns_name addr add $ipadr dev ${interface}
```

## Use case 3 - cRPD on KVM and SR-IOV
This use case covers KVM-based Virtual Machines with full-blown OS and its own routing-stack. The strength of this use case resides on their possibility to make use of more performant interfaces such as SR-IOV enabled ones. It is important to remark that for this use case, the cRPD runs on HOST mode as KVM enables a full OS.

The interesting part of this use cases resides in having 2 interfaces as we can use them to demonstrate uplink redundancy (ECMP). Thanks to this, for example, it can be shown that a running ping will not undergo packet loss even if the used link turns down as all the traffic will be inmediately shifted to the other interface.

We will now explain the setup presented in the [scenarios overview](#scenarios) section. In the host a KVM, ubuntu bionic in our case, has been deployed using virsh.For more information about KVM please refer to the [official page](https://www.linux-kvm.org/page/Main_Page). After, we have enabled VFs on an interface which allows it. To continue, we have onboarded two VFs as networking interfaces into the KVM using a xml templates. Now, we have deployed the cRPD in host mode (docker must be installed) and verified that the new interfaces are visible. Provided that the ECMP is correct, our KVM machine is empowered with uplink redun (ECMP) towards another router that we have configured acordingly in the lab.

### Use case 3 - config and setup
To launch a KVM guest:
```bash
virt-install --connect qemu:///system --virt-type kvm --name $name --ram $memory  --vcpus=$core --os-type linux --os-variant ubuntu16.04 --disk path=$image,format=qcow2 --disk cidata.iso,device=cdrom --
import --network network=default –noautoconsole
```
[To-Do] explain steps for increasing diskpspace and cloudinit
To verify that the KVM guest is running we make use of the [virsh tool](https://libvirt.org/manpages/virsh.html#description):
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

```
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

### cRPD for testing and Lab infra
The diagram shows two possibilities for the usage of the cRPD for testing use cases:
1. IFL/IFD testing
Quick test to validate 500 OSPF/iBGP-peers. Launch 500 cRPD instances, each on another IFL.
2. GRID Testing
Customer needs a quick test for a 1000-node ISIS GRID. We just might script it and launch 5 * 500 Instances on two compute-hosts.
![testing_topologies](media/testing_topologies.png)

#### Custom Topologies creation
Anyone can script the creation of their custom topology, for example for a simple twin-crpd topology as show in the below diagram:

![twin_crpds diagram](media/twin_crpds.png)

Please note, that in this case, we are runnning the cRPD in it's own networking namespace. This is different from use case 2 where we launched the crpd container in the networking namespace of another container.

```bash
#spin up crpds
docker run --rm --detach --name crpd01 -h crpd01 --privileged --net=none -v <volume_for_config>:/config -v <volume_for_varlog>:/var/log -it crpd:latest -it crpd:latest
docker run --rm --detach --name crpd01 -h crpd02 --privileged --net=none -v <volume_for_config>:/config -v <volume_for_varlog>:/var/log -it crpd:latest -it crpd:latest
#locate pids and link them for ip tool
pid1=docker inspect crpd01 --format '{{ .State.Pid }}'
pid2=docker inspect crpd02 --format '{{ .State.Pid }}'
ln -sf /proc/$pid1/ns/net /var/run/netns/crpd01
ln -sf /proc/$pid2/ns/net /var/run/netns/crpd02
#create veth
sudo ip link add crpd01-crpd02 type veth peer name crpd02-crpd01
#move legs to appropriate namespaces
sudo ip link set crpd01-crpd02 netns crpd01
sudo ip link set crpd02-crpd01 netns crpd02

#set ifaces up and provide ip addresses
sudo ip –n <namespace> <command>
```

Following this procedure more complex topologies can be created.

## CPU-Pinning

By default a docker-container can use any cores available in the system. If the host is a multi-CPU system, then any given PCI-device belongs to a specific CPU only.
In a high-performance system, the following makes sense:
- disallow (reserve/isolate) cores to be used by the linux-scheduler
- ensure that packets never traverse sockets in multi-cpu system. This means if a NIC belongs to Node 0 in a multi-cpu system, then cRPD should ideally only use cores from the same Node 0


Note: Pinning uses the CPU's which are excluded from the linux-scheduler. So excluding CPU's via "isolcpus" is only stopping the linux-scheduler to use it, but any virsh/docker can still use those CPU's



### Preparing GRUB

#### Find out nic to socket mapping

For example ens4f0 belongs to core 14-27 (numa node 1). Use the `cat /sys/bus/pci/devices/<pci-address>/local_cpulist` command to identtify to which socket the pic-address belongs.

```bash
lab@ubuntu2:~$ lspci | grep 10-G
81:00.0 Ethernet controller: Intel Corporation 82599ES 10-Gigabit SFI/SFP+ Network Connection (rev 01)
..

reverse task - providing pci-address and enlisting kernel-name

lab@ubuntu2:~$ cd /sys/bus/pci/devices
lab@ubuntu2:/sys/bus/pci/devices$ ls 0000\:81\:00.0/net/
ens4f0

lab@ubuntu2:/sys/bus/pci/devices$ ethtool -i ens4f0 | grep bus
bus-info: 0000:81:00.0

lab@ubuntu2:/sys/bus/pci/devices$ numactl -H
available: 2 nodes (0-1)
node 0 cpus: 0 1 2 3 4 5 6 7 8 9 10 11 12 13
node 0 size: 128879 MB
node 0 free: 85719 MB
node 1 cpus: 14 15 16 17 18 19 20 21 22 23 24 25 26 27
node 1 size: 129021 MB
node 1 free: 86570 MB
node distances:
node   0   1
  0:  10  21
  1:  21  10

  and HERE THE MOST IMPORTANT COMMAND (cat local_cpulist) to find out NIC<>SOCKET mapping
  ----------------------------------------------------------------------
lab@ubuntu2:/sys/bus/pci/devices$ cd /sys/bus/pci/devices/0000:81:00.0
lab@ubuntu2:/sys/bus/pci/devices/0000:81:00.0$ cat local_cpulist
14-27

```

#### /etc/default/grub

Lets assume the below *isolcpus=20-27* config in grub and below activation:

```bash
/etc/default/grub
...
GRUB_CMDLINE_LINUX_DEFAULT="intel_iommu=on"
GRUB_CMDLINE_LINUX="isolcpus=20-27 default_hugepagesz=1G hugepagesz=1G hugepages=80"
```

#### Activating changes in grub

```bash
lab@ubuntu2:~/vmx$ sudo vi /etc/default/grub
lab@ubuntu2:~/vmx$ sudo update-grub
[sudo] password for lab:
Generating grub configuration file ...
...
done

lab@ubuntu2:~/vmx$ sudo grub-install /dev/sda
Installing for x86_64-efi platform.
Installation finished. No error reported.
lab@ubuntu2:~/vmx$ sudo reboot
```

### Verify isolcpus

If the grub-parm isolcpus is active or not can be verified (after grub-update and grub-install /dev/sda and a following reboot) here:

#### /sys isolated

```bash
lab@ubuntu2:~$ cat /sys/devices/system/cpu/isolated
20-27
lab@ubuntu2:~$ cat /sys/devices/system/cpu/possible
0-27
```

#### dmesg

Futher more it might be a good idea to check of the isol-cpu was provided correctly during boot:

```bash
lab@ubuntu2:~$ cat /proc/cmdline
BOOT_IMAGE=/boot/vmlinuz-4.15.0-43-generic root=UUID=2a3f3270-84d8-434e-af28-21ea91474ff7 ro isolcpus=20-27 default_hugepagesz=1G hugepagesz=1G hugepages=80 intel_iommu=on
```

#### taskset
Just check which cpu-cores the running process is allowed to use. Core 20-27 shall not be enlisted.

```bash
lab@ubuntu2:~$ taskset -cp 1
pid 1s current affinity list: 0-19

lab@ubuntu2:~$ cat /proc/$$/status|tail -6
Cpus_allowed:   00fffff
Cpus_allowed_list:      0-19   <<<< core 20-27 not allowed, as configured via isolcpu
Mems_allowed:   00000000,00000000,00000000,00000000,00000000,00000000,00000000,00000000,00000000,00000000,00000000,00000000,00000000,00000000,00000000,00000000,00000000,00000000,00000000,00000000,00000000,00000000,00000000,00000000,00000000,00000000,00000000,00000000,00000000,00000000,00000000,00000003
Mems_allowed_list:      0-1
voluntary_ctxt_switches:        65
nonvoluntary_ctxt_switches:     0
```

### Enforce dedicated cores to be used by cRPD

By Allowing only cores 20-27 towards cRPD, we ensure that only cores are sued which belong to the desired interface ens4f0

lab@ubuntu-cg:~$ docker run --rm --detach --name crpd_01 -h crpd_01 --privileged --cpuset-cpus 20-27 --net=host -v crpd01_config:/config -v crpd01_varlog:/var/log -it crpd:20.1R1.11

## Kernel VRF with cRPD
With a kernel-VRF, cRPD is able to provide the functionality of a MPLS L3VPN. The routing-instance type must be `vrf`.

Sending and Receiving of inet.vpn unicast or inet6.vpn unicast NLRI and pushing the required MPLS label-stack is supported with cRPD.
Any routing-instance type vrf configured on the cRPD results is a vrf-table beeing created on the host automatically.

As any L3VPN config on Junos, RD, vrf-target or respective vrf-import/export policies need to be configured.
The interface to be added to the vrf must be created upfront on the host.
Assigning an ip to the auto-created loopback `__crpd-vrf<x>` for given VRF was not functional in the lab and needs further investigation.

### cRPD Configuration
An example complete configuration can be found below. Please note that for demo purposes, we have added ospf route exchange to get some routes populated into the tables.
```
routing-instances{
 kvrf1 {
    routing-options {
        router-id 192.168.53.250;
        static {
            route 192.168.240.3/32 discard;
        }
    }
    protocols {
        ospf {
            export remote_via_bgp;
            area 0.0.0.0 {
                interface all;
            }
        }
    }
    interface ens8f1.2; ## 'ens8f1.2' is not defined
    instance-type vrf;
    route-distinguisher 192.168.80.1:1;
    vrf-target target:65000:1;
}
}  
```

No difference so L3VPN config here, see MP-BGP

```
protocols {
    bgp {
replace:
        group mp-bgp {
            type internal;
            local-address 192.168.53.253;
            family inet-vpn {
                unicast;
            }
            family inet6 {
                unicast;
            }
            family inet6-vpn {
                unicast;
            }
            neighbor 192.168.53.254;
        }
    }
}
```

Note:
As of writing this doc, cRPD does not yet support LDP/SR, so any LSP requires manual setup.
The guide will be extended with output from a daily image to have LDP/SR enabled LSP's in use. Please check with PLM on official release.


  **Known issue:** cRPD reports that the vrf-interface ens8f1.2 is not defined although it is present when running 'show interfaces routing' because is not present in the [edit interfaces]  configuration section. This is expected as of now.


The result on the host of this configuration is the creation of vrfs, tables as well as enslaving the interfaces to the vrfs. It can be verified in the following way.
### Verification
List the vrfs:
```bash
lab@ubuntu-cg ~> ip link show type vrf
88: __crpd-vrf1: <MASTER,UP,LOWER_UP> mtu 65536 qdisc noqueue state UP mode DEFAULT group default qlen 1000
    link/ether fa:ca:51:01:9a:2c brd ff:ff:ff:ff:ff:ff
    alias kvrf1
```
Show the interfaces within the vrf:
```bash
lab@ubuntu-cg ~> ip addr show vrf __crpd-vrf1
83: ens8f1.2@ens8f1: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue master __crpd-vrf1 state UP group default qlen 1000
    link/ether 90:e2:ba:86:61:95 brd ff:ff:ff:ff:ff:ff
    inet 192.168.80.1/30 scope global ens8f1.2
       valid_lft forever preferred_lft forever
    inet6 fe80::92e2:baff:fe86:6195/64 scope link
       valid_lft forever preferred_lft forever
```
To know what's the table id that crpd has used for the vrf instance we can execute on the crpd the below comand, where the kernel-id: 1 is our host's table index
```
root@crpd01> show krt table | grep kvrf
kvrf1.inet.0                  : GF: 1 krt-index: 4     ID: 0 kernel-id: 1
kvrf1.iso.0                   : GF: 2 krt-index: 4     ID: 0 kernel-id: 1
kvrf1.inet6.0                 : GF: 6 krt-index: 4     ID: 0 kernel-id: 1
```
Hence, to show the content of the table :
```bash
lab@ubuntu-cg ~> ip route list table 1
broadcast 192.168.80.0 dev ens8f1.2 proto kernel scope link src 192.168.80.1
192.168.80.0/30 dev ens8f1.2 proto kernel scope link src 192.168.80.1
local 192.168.80.1 dev ens8f1.2 proto kernel scope host src 192.168.80.1
broadcast 192.168.80.3 dev ens8f1.2 proto kernel scope link src 192.168.80.1
192.168.240.1 via 192.168.80.2 dev ens8f1.2 proto 22
```

Receiving inet-vpn NLRI via above configured BGP-session

```
root@crpd01# run show route receive-protocol bgp 192.168.53.254

inet.0: 37 destinations, 38 routes (37 active, 0 holddown, 0 hidden)

inet.3: 1 destinations, 1 routes (1 active, 0 holddown, 0 hidden)

kvrf1.inet.0: 8 destinations, 8 routes (8 active, 0 holddown, 0 hidden)
  Prefix                  Nexthop              MED     Lclpref    AS path
* 192.168.53.252/32       192.168.53.254               100        I
* 192.168.240.2/32        192.168.53.254               100        I

iso.0: 1 destinations, 1 routes (1 active, 0 holddown, 0 hidden)

mpls.0: 7 destinations, 7 routes (7 active, 0 holddown, 0 hidden)

bgp.l3vpn.0: 2 destinations, 2 routes (2 active, 0 holddown, 0 hidden)
  Prefix                  Nexthop              MED     Lclpref    AS path
  192.168.53.254:1:192.168.53.252/32                    
*                         192.168.53.254               100        I
  192.168.53.254:1:192.168.240.2/32                    
*                         192.168.53.254               100        I
```

Show route receive-protocol detail to check the MPLS-labels received

```
root@crpd01# run show route receive-protocol bgp 192.168.53.254 detail 192.168.53.252/32

kvrf1.inet.0: 8 destinations, 8 routes (8 active, 0 holddown, 0 hidden)
* 192.168.53.252/32 (1 entry, 1 announced)
     Import Accepted
     Route Distinguisher: 192.168.53.254:1
     VPN Label: 300064                                 <<<< vpn label>>>>
     Nexthop: 192.168.53.254
     Localpref: 100
     AS path: I
     Communities: target:65000:1

bgp.l3vpn.0: 2 destinations, 2 routes (2 active, 0 holddown, 0 hidden)

* 192.168.53.254:1:192.168.53.252/32 (1 entry, 0 announced)
     Import Accepted
     Route Distinguisher: 192.168.53.254:1
     VPN Label: 300064
     Nexthop: 192.168.53.254
     Localpref: 100
     AS path: I
     Communities: target:65000:1
```

Checking if the routes got instelled correctly in RIB/FIB
Please note the MPLS-push

```
root@crpd01# run show route table kvrf1.inet.0

kvrf1.inet.0: 8 destinations, 8 routes (8 active, 0 holddown, 0 hidden)
+ = Active Route, - = Last Active, * = Both

192.168.53.251/32  *[OSPF/10] 3d 17:13:46, metric 1
                    >  to 192.168.80.2 via ens8f1.2
192.168.53.252/32  *[BGP/170] 3d 17:13:44, localpref 100, from 192.168.53.254
                      AS path: I, validation-state: unverified
                    >  to 192.168.100.1 via ens8f0.500, Push 300064    <<< MPLS PUSH>>>
192.168.80.0/30    *[Direct/0] 3d 17:14:01
                    >  via ens8f1.2
192.168.80.1/32    *[Local/0] 3d 17:14:01
                       Local via ens8f1.2
192.168.240.1/32   *[OSPF/150] 3d 17:13:46, metric 0, tag 0
                    >  to 192.168.80.2 via ens8f1.2
192.168.240.2/32   *[BGP/170] 3d 17:13:44, localpref 100, from 192.168.53.254
                      AS path: I, validation-state: unverified
                    >  to 192.168.100.1 via ens8f0.500, Push 300080      <<<< MPLS PUSH>>>>
192.168.240.3/32   *[Static/5] 3d 17:14:01
                       Discard
224.0.0.5/32       *[OSPF/10] 3d 17:14:01, metric 1
                       MultiRecv
```



Checking if pop-operations match the advertised routes
```
root@crpd01# run show route advertising-protocol bgp 192.168.53.254 detail

kvrf1.inet.0: 8 destinations, 8 routes (8 active, 0 holddown, 0 hidden)
* 192.168.53.251/32 (1 entry, 1 announced)
 BGP group mp-bgp type Internal
     Route Distinguisher: 192.168.80.1:1
     VPN Label: 16                      <<<< label 16 advertised>>>>
     Nexthop: Self
     Flags: Nexthop Change
     MED: 1
     Localpref: 100
     AS path: [65000] I
     Communities: target:65000:1 rte-type:0.0.0.0:1:0


root@crpd01# run show route table mpls.0

mpls.0: 7 destinations, 7 routes (7 active, 0 holddown, 0 hidden)
+ = Active Route, - = Last Active, * = Both

0                  *[MPLS/0] 3d 17:15:02, metric 1
                       Receive
1                  *[MPLS/0] 3d 17:15:02, metric 1
                       Receive
2                  *[MPLS/0] 3d 17:15:02, metric 1
                       Receive
13                 *[MPLS/0] 3d 17:15:02, metric 1
                       Receive
16                 *[VPN/170] 3d 17:14:46
                    >  to 192.168.80.2 via ens8f1.2, Pop      
16(S=0)            *[VPN/170] 3d 17:14:46
                    >  to 192.168.80.2 via ens8f1.2, Pop      <<< bottom_of_stack - matches>>>
17                 *[VPN/170] 3d 17:14:46
                       Discard
```

full config

```
root@crpd01# save terminal
## Last changed: 2020-06-08 15:44:31 UTC
version 20200319.130545_builder.r1095278;
system {
    root-authentication {
        encrypted-password "$6$.tkYp$oAmZU9IgOa4G.RVTq7yckxiAHEbZn3Vdc71TOv2/4hefozgIaw1R2LQrddLfu1QD1.bhFSTSwoEd8SvfqNDTe."; ## SECRET-DATA
    }
    inactive: processes {
        routing {
            bgp {
                rib-sharding {
                    number-of-shards 8;
                }
                update-threading {
                    number-of-threads 8;
                }
            }
        }
    }
}
interfaces {
    lo0 {
        unit 0 {
            family iso {
                address 49.1000.1921.6805.3253.00;
            }
        }
    }
}
policy-options {

    policy-statement remote_via_bgp {
        from protocol bgp;
        then accept;
    }
}
routing-instances {

    kvrf1 {
        routing-options {
            router-id 192.168.53.250;
            static {
                route 192.168.240.3/32 discard;
            }
        }
        protocols {
            ospf {
                export remote_via_bgp;
                area 0.0.0.0 {
                    interface all;
                }
            }
        }
        interface ens8f1.2;
        instance-type vrf;
        route-distinguisher 192.168.80.1:1;
        vrf-target target:65000:1;
    }

}
routing-options {
    router-id 192.168.53.253;
    autonomous-system 65000;
    rib inet.0;
    rib mpls.0;
    static {
        route 192.168.53.254/32 {
            static-lsp-next-hop to_MX480;
        }
    }
}
protocols {
    bgp {
              group mp-bgp {
            type internal;
            local-address 192.168.53.253;
            family inet-vpn {
                unicast;
            }
            family inet6 {
                unicast;
            }
            family inet6-vpn {
                unicast;
            }
            neighbor 192.168.53.254;
        }
    }
    isis {
        level 1 disable;
        interface ens8f0.500;
        interface lo.0;
        interface lo0.0;
    }
    mpls {
        label-range {
            static-label-range 1000000 1000100;
        }
        interface all;
        static-label-switched-path to_MX480 {
            ingress {
                install 192.168.53.254/32 active;
                next-hop 192.168.100.1;
                to 192.168.53.254;
            }
        }
    }
}

```


In the above output it can be verified that the last route, 192.168.240.1 was learned through OSPF (proto 22).

## Scripts and usage
Scripts for initialization of VNF's with attached cRPD as well as single interface isolated cRPDs have been created. In addition, cleanup scripts for removing the configuration are also provided

### run_vnf_and_crpd.sh
This scripts instantiates a vnf with an attached crpd connected to a physical interface though a bridge
```
useage: run_vnf_and_crpd.sh -i <interface_name> --vnf <vnf_name:tag> -c <crpd:tag> -a <ipadr> [OPTIONAL] -v (override volumes, minimum provide 2) <volume_name>:<mounting_point>
```
### destroy_vnf_and_crpd.sh
This scripts cleans up the environment after running the above mentioned script.
```
useage: destroy_vnf_and_crpd.sh -i <interface_name> --vnf <vnf_name> [OPTIONAL] -v (delete volumes)>
```
### run_single_if_crpd.sh
This script instantiates a cRPD instance with it's own networking stack and the indicated interface
```
useage: run_single_if_crpd.sh -i <interface_name> -c <crpd:tag> --name <NAME> -a <ipadr> [OPTIONAL] -v (override volumes, minimum provide 2) <volume_name>:<mounting_point>
```
To cleanup it is sufficient to destroy the crpd with `docker stop crpd_name`.
### create_crpd_netenv.sh
This script is called by the all other scripts and creates the networking configuration for crpd containers already instantiated.
```
useage: create_crpd_netenv.sh <docker_instance> <interface> <ip>
```
### cleanup_crpd_netenv.sh
This script is called by the cleanup procedures to clean the networking configuration
```
useage: cleanup_crpd_netenv.sh -i <interface_name> -n <crpd_container_name>
```
### connect_ns.sh
This script connects to provided namespaces using virtual ethernet pairs. Please note that the name of the namespaces will b used to name the veth pair. Interfaces name cannot be longer than 15 Bytes so in case the namespaces names exceed the length, they will be cropped.
```
useage: connect_ns.sh -s <src_ns> -d <dst_ns> -p <prefix30> [OPTIONAL] -h (print help)
```

## Known Issues
### Interface marked as not defined in routing instance
cRPD reports that the interface is not defined although it is present when running 'show interfaces routing' because is not present in the interfaces confiration section.
### IFL is not detected by cRPD in non-default namespace mode
When a logical interface was moved into the networking namespace where a cRPD instance was present, the cRPD was not able to pick up this interface and display it in its cli.
Juniper Engineering provided a container with the fix which has been tested in the following way.
  1. Launch the cRPD with the fix with the `--net=none` option
  ```bash
  docker run --rm --detach --name crpd01 --privileged --net=none -v crpd01_config:/config -v crpd01_varlog:/var/log -it crpd:latest
  ```
  2. Create a logical interface from a physical interface and move it to the cRPD's namepsace
  ```bash
  sudo mkdir /var/run/netns
  pid=$(docker inspect crpd01 --format '{{ .State.Pid }}')
  vid=4000

  [ -d /var/run/netns ] || sudo ln -sf /proc/$pid/ns/net /var/run/netns/$pid
  sudo ip link add link ens8f0 name ens8f0.$vid type vlan id $vid
  sudo ip link set ens8f0.$vid netns $pid
  sudo ip netns exec $pid ip link set ens8f0.$vid up
  sudo ip netns exec $pid ip addr add 192.168.203.1/30 dev ens8f0.$vid

  ```
  3. Log into the cRPD
  ```bash
  docker exec -it crpd01 cli
  ```
  4. Now check the cRPD and verify that the interface is present
  ```
  root@crpd01> show interfaces routing
  Interface        State Addresses
  ens8f0.142       Up    MPLS  enabled
                         ISO   enabled
                         INET6 fe80::92e2:baff:fe86:6194
                         INET  192.168.203.6
  lsi              Up    MPLS  enabled
                         ISO   enabled
                         INET6 fe80::a86f:e2ff:fe4e:8dac
  lo.0             Up    MPLS  enabled
                         ISO   enabled  
  ```

## Useful commands and information

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
ip -n <namespace> <command> #shortcut for the previous command
ip link set <interface> netns <namespace> # moves the interface into the specified namespace
#VNF commands
ip address # shows the interfaces and ip addresses  available in the vnf’s namespace
ip routes # Shows the ip routes known to this vnf container

```
