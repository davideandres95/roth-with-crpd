#!/bin/bash

docker run --name mynginx1 --net=none -P -d nginx
sudo ./run_vnf_and_crpd.sh -c crpd:19.4R1.10 --vnf alpine:latest -i ens8f1.141 -a 172.18.0.1/16

nginx_pid=$(docker inspect nginx --format '{{ .State.Pid }}')
crpd_pid=$(docker inspect crpd_alpine --format '{{ .State.Pid }}')

sudo ip link add veth_nginx type veth peer name vethi_nginx
sudo ip link set vethi_nginx netns $nginx_pid
sudo ip link set veth_nginx netns $crpd_pid
sudo ip netns exec $nginx_pid ip set link vethi_nginx netns up
sudo ip netns exec $crpd_pid ip set link veth_nginx netns up

sudo ip netns exec $nginx_pid ip addr add 172.18.10.2/30 dev vethi_nginx
sudo ip netns exec $crpd_pid ip addr add 172.18.10.1/30 dev veth_nginx

sudo ip netns exec $nginx_pid ip route add default via 172.18.10.1
