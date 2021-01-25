#!/usr/bin/env bash

HELP_STR="
---- Help Menu -----------------------------------------------------------------
This script stops & removes containers based on a supplied configuration file.

Options:
    -c --config-file : Optional -- Filepath to a configuration file that will be 
                       used to configure the containers and installation. 
                       
                       Default -- THIS_SCRIPT_DIR/config/config.template.yml

Examples:
    ./down.sh
    ./down.sh -c config/config.yml
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
    
    pretty_header "D D  D O W N" 1

    # Set config file
    export CONFIG_FILE=$DD_CONFIG_FILE

     # Ensure containers do not already exist/are not up
    get_docker_kagent_image_name "KAGENT_IMAGE"
    get_docker_kinetica_image_name "KINETICA_IMAGE"
    container_validation $KAGENT_IMAGE $KINETICA_IMAGE "down"

    # Stop and remove the containers
    pretty_header "Stop & Remove" 2
    get_docker_compose_config "DOCKER_CONFIG"
    get_docker_project_name "PROJECT_NAME"
    run_cmd "docker-compose -f ${DOCKER_CONFIG} -p $PROJECT_NAME down"

}

main