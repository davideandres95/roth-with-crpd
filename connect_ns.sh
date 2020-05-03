#!/bin/bash

#check if root
if [[ $EUID -ne 0 ]];
    then
         echo "This script must be run as root" 1>&2
         exit
fi


PARAMS=""
while (( "$#" )); do
    case "$1" in
        -h|--help)
          print_help
          exit 1
          ;;
        -s|--src)
          SRC=$2
          shift
          ;;
        -d|--dst)
          DST=$2
          shift
          ;;
        -p|--prefix-30)
          PREFIX_30=$2
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
# set positional arguments in their propper place
eval set -- "$PARAMS"

if [[ -n $SRC ]] && [[ -n $DST ]]; then
  sudo ip link add veth_${SRC}_${DST} type veth peer name veth_${DST}_${SRC}
  sudo ip link set veth_${DST}_${SRC} netns $SRC
  sudo ip link set veth_${DST}_${SRC} netns $DST
  sudo ip -n $SRC set veth_${DST}_${SRC} up
  sudo ip -n $DST set veth_${SRC}_${DST} up
  if [[ -n $PREFIX_30 ]]; then
      sudo ip -n $SRC addr add $PREFIX_30.1 dev veth_${SRC}_${DST}
      sudo ip -n $DST addr add $PREFIX_30.2 dev veth_${DST}_${SRC}
  fi
else
    print_help
    exit 1
fi
