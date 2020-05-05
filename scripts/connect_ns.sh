#!/bin/bash

#check if root
if [[ $EUID -ne 0 ]];
    then
         echo "This script must be run as root" 1>&2
         exit
fi
print_help () {
	echo "useage: $0 -s <src_ns> -d <dst_ns> -p <prefix30> [OPTIONAL] -h (print help)"
}



PARAMS=""
while (( "$#" )); do
    case "$1" in
        -h|--help)
          print_help
          exit 1
          ;;
        -s|--src)
	  SRC=$2
	  s_if=${2:(-7)}
          shift
          ;;
        -d|--dst)
          DST=$2
          d_if=${2:(-7)}
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
    #create veth pair with name src-dst
    sudo ip link add ${s_if}-${d_if} type veth peer name ${d_if}-${s_if}
    sudo ip link set ${s_if}-${d_if} netns $SRC
    sudo ip link set ${d_if}-${s_if} netns $DST
    sudo ip -n $SRC link set ${s_if}-${d_if} up
    sudo ip -n $DST link set ${d_if}-${s_if} up
    if [[ -n $PREFIX_30 ]]; then
        sudo ip -n $SRC addr add $PREFIX_30.1 dev ${s_if}-${d_if}
        sudo ip -n $DST addr add $PREFIX_30.2 dev ${d_if}-${s_if}
    fi
else
    print_help
    exit 1
fi
