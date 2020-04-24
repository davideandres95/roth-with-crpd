#!/bin/bash

c_cleanup () {
    echo "Looking for containers pid"
    PID=$(docker inspect $DOCKER_INSTANCE --format '{{ .State.Pid }}') # get pid of docker-instance
    #check if the container still lives
    if [ -z $PID ];
        then 
	    echo "no crpd docker container running. Please clean up before stopping the container."
	    exit 1
    fi
    echo "Found PID of docker $DOCKER_INSTANCE: $PID"
    pid_cleanup
}

pid_cleanup () {
    veth_main=veth_${PID}
    veth_instance=vethi_${PID}

    # delete bridge
    bridge=crpd_${PID}
    echo "deleting bridge: $bridge ..."
    brctl delif ${bridge} ${veth_main} # remove veth_main from bridge
    brctl delif ${bridge} ${INTERFACE} # remove physical interface from bridge
    ip link set ${bridge} down  # disable the bridge
    brctl delbr ${bridge} # delete bridge with name of docker_instance
    if [[ $(brctl show | grep ${bridge}) ]]; then
        #the bridge still exists
        echo "Error: The bridge $bridge could not be cleaned. However, the cleanup will continue continue" >&2
    else
        echo "The bridge $bridge was successfully deleted"
    fi
    # delete veth pair
    echo ${veth_main}
    echo ${veth_instance}
    ip link delete ${veth_main} type veth peer name ${veth_instance}  # create veth pair

    # remove the symlink to the dockers container namespace if present
    if [ -e /var/run/netns/${PID} ];
        then 
             rm /var/run/netns/${PID}
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
    -p|--pid)
      PID=$2
      shift 2
      ;;
    -i|--interface)
      INTERFACE=$2
      shift 2
      ;;
    -d|--docker)
      DOCKER_INSTANCE=$2
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

if [[ -n $PID ]] && [[ -n $INTERFACE ]];
then
    pid_cleanup
elif [[ -n $DOCKER_INSTANCE ]] && [[ -n $INTERFACE ]];
then
    c_cleanup
else
    echo "useage: $0 -i <interface_name> -p <PID> OR $0 -i <interface_name> -d <docker_instance_name>"
    echo "Error: bad params combi. Maybe interface is missing" >&2
    exit 1
fi
