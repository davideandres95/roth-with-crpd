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
    #move the interface back to the
    ip -n ${PID} link set $INTERFACE netns 1
    ip link set $INTERFACE down
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
