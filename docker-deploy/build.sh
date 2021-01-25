#!/usr/bin/env bash

HELP_STR="
---- Help Menu -----------------------------------------------------------------
This script builds Docker images specified in a supplied configuration file that
will be prepped for KAgent/Kinetica installation.

Options:
    -f --kagent-file : Required -- Filepath to a 7.1 KAgent RPM

    -c --config-file : Optional -- Filepath to a configuration file that will be 
                       used to configure the containers and installation. 
                       
                       Default -- THIS_SCRIPT_DIR/config/config.template.yml

Examples:
    ./build.sh -f ~/Downloads/kagent-7.1.1.0.latest-0.ga-0.x86_64.el7.rpm
    ./build.sh -f ~/Downloads/kagent-7.1.1.0.latest-0.ga-0.x86_64.el7.rpm /
        -c config/config.yml
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

    -f|--kagent-file)
        shift; KAGENT_FILE="$1"
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

    pretty_header "D D  B U I L D" 1

    # Set config file
    export CONFIG_FILE=$DD_CONFIG_FILE

    # Validate the provided KAgent RPM and config files
    pretty_header "KAgent RPM Validation" 2
    if [ -z $KAGENT_FILE ]; then
        log "ERROR: No KAgent file location provided. Please run the script again with a file specified."
        exit 1
    else
        # Ensure 'packages/' directory exists
        if [ -d "${THIS_SCRIPT_DIR}/packages" ]; then
            :
        else
            run_cmd "mkdir packages/"
        fi

        # Ensure the RPM is in the 'packages/' directory
        RPM=$(basename ${KAGENT_FILE})
        if [ -e "${THIS_SCRIPT_DIR}/packages/${RPM}" ]; then
            log "KAgent RPM '${RPM}' is available in '${THIS_SCRIPT_DIR}/packages'!"
        else
            run_cmd "cp ${KAGENT_FILE} packages/"
            log "Copied KAgent RPM '${KAGENT_FILE}' to '${THIS_SCRIPT_DIR}/packages'!"
        fi
    fi
    log

    # Generate Kinetica docker file + SSHD script
    pretty_header "Kinetica Docker Config Generation" 2
    get_docker_compose_config "DOCKER_CONFIG"
    get_provision_on_prem_sshd_setup_script "SSHD_SETUP_SCRIPT"
    generate_docker_compose_config_file "${DOCKER_CONFIG}"
    generate_docker_sshd_setup_file "${SSHD_SETUP_SCRIPT}"

    # Compose the images
    pretty_header "Docker Compose" 2
    get_docker_project_name "PROJECT_NAME"
    # ~~~debug options: --no-cache --pull
    run_cmd "docker-compose -f ${DOCKER_CONFIG} \
        -p ${PROJECT_NAME} build \
        --parallel --compress --force-rm \
        --build-arg RPM=${RPM} \
        --build-arg USER=$(whoami)"
    log

    find_untagged_images

}

main