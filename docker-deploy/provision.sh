#!/usr/bin/env bash

HELP_STR="
---- Help Menu -----------------------------------------------------------------
This script provisions/installs Kinetica. Provision type is governed by the
provided config file.

Supported Provision Types:
    - onprem

Options:
    -c --config-file : Optional -- Filepath to a configuration file that will be 
                       used to configure the containers and installation. 
                       
                       Default -- THIS_SCRIPT_DIR/config/config.template.yml

Examples:
    ./provision.sh
    ./provision.sh -c config/config.yml
--------------------------------------------------------------------------------
"


THIS_SCRIPT=$(basename ${BASH_SOURCE[0]})
THIS_SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"


# Source script(s)
source ${THIS_SCRIPT_DIR}/utils/common.sh
source ${THIS_SCRIPT_DIR}/utils/config-utils.sh
source ${THIS_SCRIPT_DIR}/utils/docker-utils.sh
source ${THIS_SCRIPT_DIR}/utils/provision-utils.sh

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

main() {

    pretty_header "D D  P R O V I S I O N" 1

    # Set config file
    export CONFIG_FILE=$DD_CONFIG_FILE

    # Ensure containers do not already exist/are not up
    get_docker_kagent_image_name "KAGENT_IMAGE"
    get_docker_kagent_image_name "KINETICA_IMAGE"
    container_validation $KAGENT_IMAGE $KINETICA_IMAGE "provision"

    pretty_header "Provision / Install Kinetica" 2

    # Get deployment type and KAgent image name; export environment variables
    # used in utils/provision-utils.sh
    get_provision_deploy "DEPLOYMENT_TYPE"
    get_docker_kagent_image_name "KAGENT"
    export KAGENT=$KAGENT
    export KAGENT_EXE="/opt/gpudb/kagent/bin/kagent"
    export KAGENT_CONTAINER_BASH="docker exec --user gpudb ${KAGENT} bash -c"

    # Copy config file to KAgent container
    # run_cmd "docker cp utils/provision-utils.sh ${KAGENT}:/home/utils/" # debug~~~
    # run_cmd "docker cp utils/common.sh ${KAGENT}:/home/utils/" # debug~~~
    run_cmd "docker cp ${DD_CONFIG_FILE} ${KAGENT}:/home/config/"
    log

    # Provision/install nodes based on deployment type
    provision_kinetica $DEPLOYMENT_TYPE
    log

    if [[ $DEPLOYMENT_TYPE == "onprem" ]]; then
       # Ensure stats is started
      pretty_header "Start 'kinetica_stats'" 2
      run_cmd "docker exec ${KAGENT} /etc/init.d/kinetica_stats start"
      log

      # Capture the mapped ports
      source ${THIS_SCRIPT_DIR}/utils/ports.sh -c $DD_CONFIG_FILE | tee ports.txt
    fi

}

main
