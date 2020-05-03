#!/bin/bash

#check if root
if [[ $EUID -ne 0 ]];
    then
         echo "This script must be run as root" 1>&2
         exit
fi

print_help () {
    echo "useage: $0 -i <interface_name> --vnf <vnf_name> [OPTIONAL] -v (delete volumes)>"
}
request_confirmation () {
    read -p "Are you sure you want to delete de Volumes? (Y/N) " -n 1 -r
    echo    # (optional) move to a new line
    if [[ $REPLY =~ ^[Yy]$ ]];then
        CONFIRMED=true# do dangerous stuff
    fi
}

PARAMS=""
while (( "$#" )); do
    case "$1" in
        -h|--help)
          print_help
          exit 1
          ;;
        -v|--delete-volumes)
          DELETE_VOLUMES=true
          CONFIRMED=false #force user to confirm deletion
          shift
          ;;
        --vnf)
          VNF=$2
          CRPD="crpd_${VNF}"
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
# set positional arguments in their propper place
eval set -- "$PARAMS"

if [[ -n $VNF ]] && [[ -n $INTERFACE ]]; then
    ./cleanup_crpd_netenv.sh -i $INTERFACE -d $CRPD
    echo "Stopping containers..."
    docker stop $VNF
    docker stop $CRPD
    if [[ $DELETE_VOLUMES ]]; then
        request_confirmation
        if [[ $CONFIRMED ]]; then
            echo "Deleteing volumes..."
            docker volume rm ${CRPD}_config
            docker volume rm ${CRPD}_varlog
        fi
    fi
    echo "Stop procedure finished"
else
    print_help
    exit 1
fi
