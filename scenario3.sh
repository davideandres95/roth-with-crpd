docker run --rm --detach --name crpd02 -h crpd02 --privileged --net=host -v crpd02_config:/config -v crpd02_varlog:/var/log -it crpd:20.1R1.11
