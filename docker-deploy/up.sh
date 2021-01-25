#!/usr/bin/env bash

HELP_STR="
---- Help Menu -----------------------------------------------------------------
This script starts-up containers based on a supplied configuration file.

Options:
    -c --config-file : Optional -- Filepath to a configuration file that will be 
                       used to configure the containers and installation. 
                       
                       Default -- THIS_SCRIPT_DIR/config/config.template.yml

Examples:
    ./up.sh
    ./up.sh -c config/config.yml
--------------------------------------------------------------------------------
"


THIS_SCRIPT=$(basename ${BASH_SOURCE[0]})
THIS_SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"


# Source script(s)
source ${THIS_SCRIPT_DIR}/utils/common.sh
source ${THIS_SCRIPT_DIR}/utils/config-utils.sh
source ${THIS_SCRIPT_DIR}/utils/docker-utils.sh

# Logging setup
DATE="$(date +%F_%T)"
log_setup "${THIS_SCRIPT_DIR}/logs" "${THIS_SCRIPT%.*}_${DATE}.log"
export LOG=${THIS_SCRIPT_DIR}/logs/${THIS_SCRIPT%.*}_${DATE}.log

# Defaults
DD_CONFIG_FILE="${THIS_SCRIPT_DIR}/config/config.template.yml"

while [[ "$1" =~ ^- && ! "$1" == "--" ]]; do case $1 in

    -h|--help)
        # Print the help menu then exit
        echo "$HELP_STR"
        exit 0
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

main () {

    pretty_header "D D  U P" 1

    # Set config file
    export CONFIG_FILE=$DD_CONFIG_FILE

    # Check if the required directories exist. If they do, see if they're empty;
    # if they don't, create them
    get_docker_mount_base_dir "MOUNT_BASE_DIRECTORY"
    REQUIRED_DIRS=(${MOUNT_BASE_DIRECTORY})
    dir_setup ${REQUIRED_DIRS[@]}

    # Ensure containers do not already exist/are not up
    get_docker_kagent_image_name "KAGENT_IMAGE"
    get_docker_kinetica_image_name "KINETICA_IMAGE"
    container_validation $KAGENT_IMAGE $KINETICA_IMAGE "up"

    # Bring the containers up
    pretty_header "Start" 2
    get_docker_compose_config "DOCKER_CONFIG"
    get_docker_project_name "PROJECT_NAME"
    run_cmd "docker-compose -f ${DOCKER_CONFIG} -p ${PROJECT_NAME} up -d"

    # For onprem deployments, chown /opt/gpudb recursively to gpudb:gpudb
    get_provision_deploy "DEPLOYMENT_TYPE"
    if [[ $DEPLOYMENT_TYPE == "onprem" ]]; then
      KINETICA_CONTAINER_IDS=$(docker ps -a | egrep -i "${KINETICA_IMAGE}" | awk '{print $1}')
      for id in $KINETICA_CONTAINER_IDS
      do
         docker exec $id bash -c "chown -R gpudb:gpudb /opt/gpudb"
      done
    fi
}

main