#!/bin/bash

name_cleanup () {
    #move the interface back to the default namespace
    ip -n $NAME link set $INTERFACE netns 1
    ip link set $INTERFACE down
    # remove the symlink to the dockers container namespace if present
    if [[ -e /var/run/netns/$NAME ]]; then
        sudo rm /var/run/netns/$NAME
    fi
    echo "cleanup finished"
}

# check if root
if [[ $EUID -ne 0 ]];
   then
	echo "This script must be run as root" 1>&2
	exit
fi

PARAMS=""
while (( "$#" )); do
  case "$1" in
    -n|--name)
      NAME=$2
      shift 2
      ;;
    -i|--interface)
      INTERFACE=$2
      shift 2
      ;;
    --) # end argument parsing
      shift
      break
      ;;
    -*|--*=) # unsupported param
      echo "Error: Unsupported param $1" >&2
      exit 1
      ;;
    *) # preserve positional arguments
      PARAMS="$PARAMS $1"
      shift
      ;;
  esac
done
# set positional arguments in their proper place
eval set -- "$PARAMS"

if [[ -n $NAME ]] && [[ -n $INTERFACE ]]; then
    name_cleanup
else
    echo "useage: $0 -i <interface_name> -n <crpd_container_name>"
    echo "Error: bad params combi. Maybe interface is missing" >&2
    exit 1
fi
