#!/bin/bash

#check if root
if [[ $EUID -ne 0 ]];
    then
         echo "This script must be run as root" 1>&2
         exit
fi

#change to the scripts directory
cd ~/scripts

print_help () {
    echo "useage: $0 -i <interface_name> -c <crpd:tag> --name <NAME> -a <ipadr> [OPTIONAL] -v (override volumes, minimum provide 2) <volume_name>:<mounting_point>"
}

create_vol () {
#check if volumes exist. If not, create them.
    if [[ ! $(docker volume ls | grep -q $1; echo $?) ]];
        then
            echo "docker volume $1 does not exist. Creating..."
            docker volume create $1
            echo "docker volume $1 created"
        else
            echo "docker volume $1 already present. Will be reutilised..."
    fi
}

prepare_vols () {
    cnt=${#VOLUMES[@]}
    for ((i=0;i<cnt;i++)); do
        VOLUMES[i]="-v ${VOLUMES[i]}"
        vols_string="$vols_string ${VOLUMES[i]}"
    done
}

PARAMS=""
vols_string=""
VOLUMES=()
while (( "$#" )); do
    case "$1" in
        -h|--help)
          print_help
          exit 1
          ;;
        -v|--override-volumes)
          VOLUMES+=($2)
          shift
          ;;
        -c|--crpd)
          CRPD=$2
          shift 2
          ;;
        -i|--interface)
          INTERFACE=$2
          shift 2
          ;;
        -a|--address)
          IPADR=$2
          shift 2
          ;;
        -h|--help)
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

if [[ -n $VNF ]] && [[ -n $CRPD ]] && [[ -n $INTERFACE ]] && [[ -n $IPADR ]]; then
    if [[ ${#VOLUMES[@]} -ge 2 ]]; then
	      echo "overriding default volumes.."
        for i in ${VOLUMES[@]}; do
            create_vol "$(cut -d':' -f1 <<< $i)"
        done
    elif [[ ${#VOLUMES[@]} -eq 1 ]]; then
        echo "Error: At least two volumes are required. Only one was provided" >&2
        exit 1
    elif [[ ${#VOLUMES[@]} -eq 0 ]]; then
        echo "using default volumes"
        crpd_config_vol="crpd_${VNF}_config"
        crpd_var_vol="crpd_${VNF}_varlog"
        VOLUMES=(${VOLUMES[@]} "$crpd_config_vol:/config")
        VOLUMES=(${VOLUMES[@]} "$crpd_var_vol:/var/log")
        for i in ${VOLUMES[@]}; do
            create_vol $i
        done
    fi
    crpd_name="crpd_${VNF}"
    prepare_vols
    echo "Starting containers..."
    docker run --rm --detach --name $VNF -h $VNF --privileged --net=none -it ${VNF}:${VNF_TAG}
    docker run --rm --detach --name $crpd_name --privileged --net=container:$VNF $vols_string -it $CRPD
    ./create_crpd_veths.sh $crpd_name $INTERFACE $IPADR
    #./setup_crpd_networking.sh $crpd_name $INTERFACE $IPADR
    echo "Start procedure finished"
else
    print_help
    exit 1
fi
