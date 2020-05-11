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

nextIp () {
    IP=$1
    IP_HEX=$(printf '%.2X%.2X%.2X%.2X\n' `echo $IP | sed -e 's/\./ /g'`)
    NEXT_IP_HEX=$(printf %.8X `echo $(( 0x$IP_HEX + 1 ))`)
    NEXT_IP=$(printf '%d.%d.%d.%d\n' `echo $NEXT_IP_HEX | sed -r 's/(..)/0x\1 /g'`)
    echo "$NEXT_IP"
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
	  s_if=${s_if:=$SRC}
	  echo "s_if=$s_if"
          shift
          ;;
        -d|--dst)
          DST=$2
          d_if=${2:(-7)}
	  d_if=${d_if:=$DST}
	  echo "d_if=$d_if"
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
        IP_1=$(nextIp $PREFIX_30)
	echo "${s_if}-${d_if} interface has: ${IP_1}"
	IP_2=$(nextIp $IP_1)
	echo "${d_if}-${s_if} interface has: $IP_2"
        sudo ip -n $SRC addr add $IP_1 dev ${s_if}-${d_if}
        sudo ip -n $DST addr add $IP_2 dev ${d_if}-${s_if}
    fi
else
    print_help
    exit 1
fi
