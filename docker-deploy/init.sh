#!/usr/bin/env bash

HELP_STR="
---- Help Menu -----------------------------------------------------------------
This script will initialize a Kinetica setup for you using the provided
configuration file, i.e. run build.sh, up.sh, and provision.sh sequentially
rather than piecemeal.

Supported Provision Types:
    - onprem

Options:
    -f --kagent-file : Required -- Filepath to a 7.1 KAgent RPM

    -v --skipconfig  : Optional -- Skip validation of the provided configuration 
                       file

                       Default -- False (0)

    -b --skipbuild   : Optional -- Skip building the KAgent and Kinetica images; 
                       provisioning will use images that are available locally 
                       that match the provided configuration file

                       Default -- False (0)

    -c --config-file : Optional -- Filepath to a configuration file that will be 
                       used to configure the containers and installation. 

                       Default -- THIS_SCRIPT_DIR/config/config.template.yml

Examples:
    ./init.sh
--------------------------------------------------------------------------------
"


THIS_SCRIPT=$(basename ${BASH_SOURCE[0]})
THIS_SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"


# Source script(s)
source ${THIS_SCRIPT_DIR}/utils/common.sh
source ${THIS_SCRIPT_DIR}/utils/config-utils.sh

# Logging setup
DATE="$(date +%F_%T)"
log_setup "${THIS_SCRIPT_DIR}/logs" "${THIS_SCRIPT%.*}_${DATE}.log"
export LOG=${THIS_SCRIPT_DIR}/logs/${THIS_SCRIPT%.*}_${DATE}.log

# Defaults
DD_CONFIG_FILE="${THIS_SCRIPT_DIR}/config/config.template.yml"
SKIP_CONFIG_VALIDATION=0
SKIP_BUILD=0

while [[ "$1" =~ ^- && ! "$1" == "--" ]]; do case $1 in

    -h|--help)
        # Print the help menu then exit
        echo "$HELP_STR"
        exit 0
        ;;

    -c|--config-file)
        shift; DD_CONFIG_FILE="$1"
        ;;

    -f|--kagent-file)
        shift; KAGENT_FILE="$1"
        ;;

    -v|--skipconfig)
        shift; SKIP_CONFIG_VALIDATION=1
        ;;

    -b|--skipbuild)
        shift; SKIP_BUILD=1
        ;;

    *)
        echo "ERROR: Unknown option: $1" >&2
        exit 1
        ;;

esac; shift; done
if [[ "$1" == '--' ]]; then shift; fi

main() {

  log "&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&"
  log "%%%%%                                                              %%%%%"
  log "%%%%%        I N I T I A L I Z E  D O C K E R  D E P L O Y         %%%%%"
  log "%%%%%                                                              %%%%%"
  log "&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&"
  log

  # Validate the provided config file
  if [ $SKIP_CONFIG_VALIDATION -eq 0 ]; then
    config_validation $DD_CONFIG_FILE
    log "Configuration file validated successfully!"
    log
  fi
  export CONFIG_FILE=$DD_CONFIG_FILE

  # Build the images
  if [ $SKIP_BUILD -eq 0 ]; then
    source build.sh --config-file $DD_CONFIG_FILE --kagent-file $KAGENT_FILE
  fi

  # Bring the containers up
  source up.sh --config-file $DD_CONFIG_FILE
  log

  # Provision/install Kinetica
  source provision.sh --config-file $DD_CONFIG_FILE

}

main