#!/usr/bin/env bash

HELP_STR="
---- Help Menu -----------------------------------------------------------------
This script prints the locally-mapped ports for the Kinetica and KAgent 
containers.

Options:
    --adhoc : Optional -- Prints ports to std out (requires 
              common.sh & config-utils.sh to be loaded)

    -c --config-file : Optional -- Filepath to a configuration file that will be 
                    used to configure the containers and installation. 
                    
                    Default -- THIS_SCRIPT_DIR/../config/config.template.yml

Examples:
    ./ports.sh
    ./ports.sh --adhoc
    ./ports.sh --adhoc --config-file ../config/config.yml
--------------------------------------------------------------------------------
"


THIS_SCRIPT=$(basename ${BASH_SOURCE[0]})
THIS_SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"


# Defaults
DD_CONFIG_FILE="${THIS_SCRIPT_DIR}/../config/config.template.yml"

while [[ "$1" =~ ^- && ! "$1" == "--" ]]; do case $1 in

    -h|--help)
        # Print the help menu then exit
        echo "$HELP_STR"
        exit 0
        ;;

    --adhoc)
        shift; 
        # Source script(s)
        source ${THIS_SCRIPT_DIR}/common.sh
        source ${THIS_SCRIPT_DIR}/config-utils.sh
        ;;

    -c|--config-file)
        shift; DD_CONFIG_FILE="$1"
        ;;

    *)
        echo "ERROR: Unknown option: $1" >&2
        exit 1
        ;;

esac; shift; done
if [[ "$1" == '--' ]]; then shift; fi

main() {

  # Set config
  export CONFIG_FILE=$DD_CONFIG_FILE
  # export CONFIG_FILE=${THIS_SCRIPT_DIR}/../config/config.yml # debug~~~

  pretty_header "Mapped Ports" 2

  # Get KAgent image name & container ID and use that to get the ports
  pretty_header "KAgent" 4
  get_docker_kagent_image_name "KAGENT_IMAGE"
  KAGENT_CONTAINER_ID=$(docker ps -a | egrep -i "${KAGENT_IMAGE}" | awk '{print $1}')
  echo "IMAGE NAME   : $KAGENT_IMAGE"
  echo "CONTAINER ID : $KAGENT_CONTAINER_ID"
  echo
  echo "CONTAINER PORT          HOST PORT"
  docker inspect $KAGENT_CONTAINER_ID | jq '.[0].NetworkSettings.Ports | keys[] as $k | "\($k)               \(.[$k] | .[0].HostPort)"'
  echo

  # Get the Kinetica image name and container ID(s) and use those to get the 
  # ports
  pretty_header "Kinetica" 4
  get_docker_kinetica_image_name "KINETICA_IMAGE"
  echo "IMAGE NAME : $KINETICA_IMAGE"
  pretty_header "divider"
  KINETICA_CONTAINER_IDS=$(docker ps -a | egrep -i "${KINETICA_IMAGE}" | awk '{print $1}')
  for id in $KINETICA_CONTAINER_IDS; do
    echo "CONTAINER ID   : $id"
    echo "CONTAINER NAME : $(docker inspect $id | jq '.[0].Name')"
    echo
    echo "CONTAINER PORT          HOST PORT"
    docker inspect $id | jq '.[0].NetworkSettings.Ports | keys[] as $k | "\($k)               \(.[$k] | .[0].HostPort)"'
    pretty_header "divider"
  done

}

main
