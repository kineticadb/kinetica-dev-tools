#!/usr/bin/env bash

# This script only defines common functions used in all the scripts.
# You must set the environment variable LOG=logfile.txt to capture the output.

# Import other utility scripts
# SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# ROOT_DIR="$SCRIPT_DIR/.."
# COMMON_SCRIPTS_DIR="$SCRIPT_DIR"

# echo $SCRIPT_DIR
# echo $ROOT_DIR
# echo $COMMON_SCRIPTS_DIR

# Import the config file parser and docker utils
# source "$COMMON_SCRIPTS_DIR/config-utils.sh"
# source "$COMMON_SCRIPTS_DIR/docker-utils.sh"

# ---------------------------------------------------------------------------
# Echo to the $LOG file

function log
{
    echo "${@:-}" | tee -a $LOG
}

# ---------------------------------------------------------------------------
# Run a command and append output to $LOG file which should have already been set.

function run_cmd
{
    local CMD=$1
    #LOG=$2 easier to just use the global $LOG env var set in functions below

    echo " "  >> $LOG
    echo "$CMD" 2>&1 | tee -a $LOG
    eval "$CMD" 2>&1 | tee -a $LOG

    #ret_code=$? this is return code of tee
    local ret_code=${PIPESTATUS[0]}
    if [ $ret_code != 0 ]; then
        printf "Error : [%d] when executing command: '$CMD'\n" $ret_code
        echo "Please see log file: $LOG"
        exit 1
    fi
}

# ---------------------------------------------------------------------------
# Pretty print section headers

function pretty_header
{

    ############################################################################
    #
    # This function uses the given text to pretty print a template header.
    #
    # The available arguments are as follows:
    #
    # * TEXT  : Text string to pretty print
    # * LEVEL : Heading level
    #
    ############################################################################

    local __TEXT=$1
    local __LEVEL=$2

    if [[ $__LEVEL -eq 1 ]]; then
        log "##################################################################"
        log "@@@@@                                                        @@@@@"
        log "@@@@@ ${__TEXT}                                                   "
        log "@@@@@                                                        @@@@@"
        log "##################################################################"
        log ""
    elif [[ $__LEVEL -eq 2 ]]; then
        log "##################################################################"
        log "@@ ${__TEXT}                                                      "
        log "##################################################################"
        log ""
    elif [[ $__LEVEL -eq 3 ]]; then
        log "##################################################################"
        log "##################################################################"
        log "##### ${__TEXT} "
        log "##################################################################"
        log "##################################################################"
        log ""
    elif [[ $__LEVEL -eq 4 ]]; then
        log "##################################################################"
        log "##### ${__TEXT} "
        log "##################################################################"
        log ""
    else
        log ""
        log "------------------------------------------------------------------"
        log ""
    fi

}

# ---------------------------------------------------------------------------
# Mount Directory setup

function dir_setup
{

    ############################################################################
    #
    # This function uses the given arguments to check if a required directory
    # exists. If the directory does not exist, it will be created.
    #
    # The available arguments are as follows:
    #
    # * DIRS : Array of directories to setup prior to workflow to avoid any
    #          unnecessary errors
    #
    ############################################################################

    local __DIRS=("$@")

    pretty_header "Directory Setup" 4

    for dir in ${__DIRS[@]}; do
        # Check to see if directory exists
        if [ -d "${dir}" ]; then
            log "- Required directory '${dir}' exists!"

            # Check to see if directory is empty
            if [ "$(ls -A ${dir})" ]; then
                log "  - '${dir}' is currently not empty."
                log "  - Do you want to remove everything under '${dir}*' (y/n)?"
                read CONFIRM_MOUNT_REMOVE
                if [ $CONFIRM_MOUNT_REMOVE == "y" ] || [ $CONFIRM_MOUNT_REMOVE == "Y" ]; then
                    log "    - Confirmed. Removing contents."
                    run_cmd "rm -rf ${dir}*"
                else
                    log "    - Unconfirmed. Not removing contents."
                fi
            else
                log "   - '${dir}' is currently empty. No need to clean-up."
            fi

        else
            log "- Required directory '${dir}' DOES NOT exist! Creating now."
            run_cmd "mkdir ${dir}"
        fi
    done
    log

}


##############################################################################
#  Checks if the OS run on this machine is Mac OS or Linux.
#
#  Arguments:
#  * 1st arg -- the name of the output variable
#
#  Returns:
#      1 if Mac OS, 0 if linux.
##############################################################################
function is_mac_os
{
    local OUTPUT_VAR_NAME="$1"

    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        # Got linux
        IS_MAC_OS=0
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        # Mac OSX
        IS_MAC_OS=1
    # The commented out section is for the future
    # elif [[ "$OSTYPE" == "cygwin" ]]; then
    #     # POSIX compatibility layer and Linux environment emulation for Windows
    # elif [[ "$OSTYPE" == "msys" ]]; then
    #     # Lightweight shell and GNU utilities compiled for Windows (part of MinGW)
    # elif [[ "$OSTYPE" == "win32" ]]; then
    #     # I'm not sure this can happen.
    # elif [[ "$OSTYPE" == "freebsd"* ]]; then
    #     # ...
    else
        # Unknown
        IS_MAC_OS=0
    fi

    # Need to save the result in the final output argument
    eval "$OUTPUT_VAR_NAME=$IS_MAC_OS"
} # end is_mac_os


# ---------------------------------------------------------------------------
# Img cleanup

function find_untagged_images
{

    ############################################################################
    #
    # When called, this function will search for images without tags, i.e.
    # a tag of '<none>'. If found, the function will prompt the user to cleanup
    # the untagged images.
    #
    ############################################################################

    pretty_header "Find Untagged Images" 2

    UNTAGGED_IMAGES=$(docker image list | grep '<none>')
    if [ ! -z "$UNTAGGED_IMAGES" ]; then

        log "Found some untagged images most likely resulting from the recent build operation:"
        log "REPOSITORY               TAG                 IMAGE ID            CREATED              SIZE"
        run_cmd "docker image list | grep '<none>'"
        log

        log "Do you want to cleanup these untagged images (y/n)?"
        read CONFIRM_IMAGE_CLEANUP
        log

        if [ $CONFIRM_IMAGE_CLEANUP == "y" ] || [ $CONFIRM_IMAGE_CLEANUP == "Y" ]; then
            log "Confirmed. Cleaning-up."
            log ""
            UNTAGGED_IMAGE_IDS=$(docker image list | grep '<none>' | awk '{print $3}')
            for id in $UNTAGGED_IMAGE_IDS; do
                log "Removing ${id}..."
                run_cmd "docker image rm -f ${id}"
                log
            done

        else
            log "Unconfirmed. Not cleaning-up."
        fi
    else
        log "No untagged images found!"
    fi
    log

}

# ---------------------------------------------------------------------------
# Container validation

function container_validation
{

    ############################################################################
    #
    # This function uses the given arguments to determine if specified KAgent
    # and/or Kinetica containers are already running.
    #
    # The available arguments are as follows:
    #
    # * KAGENT_REPO        : Docker repository name for the KAgent image
    # * KINETICA_REPO      : Docker repository name for the Kinetica image
    # * UP_DOWN            : The desired action: bring containers up or down
    #
    ############################################################################

    local __KAGENT_REPO=$1
    local __KINETICA_REPO=$2
    local __UP_DOWN=$3

    pretty_header "Container Validation" 2

    pretty_header "KAgent" 4
    # Check to see if any KAgent images exist
    if [ "$(docker images -q "${__KAGENT_REPO}" 2> /dev/null)" == "" ]; then
        # KAgent image does not exist
        log "ERROR: No images found for ${__KAGENT_REPO} repository. Try building first."
        exit 1
    else
        # KAgent image does exist; check to see if any started KAgent containers
        KAGENT_CONTAINER_RUNNING=0
        KAGENT_CONTAINER_ID=$(docker ps -a | egrep -i "${__KAGENT_REPO}" | awk '{print $1}')
        if [ "${KAGENT_CONTAINER_ID}" == "" ]; then
            # KAgent container not started
            log "No ${__KAGENT_REPO} container started."
        else
            # KAgent container started; check its status
            KAGENT_CONTAINER_STATUS_CHECK=$(docker inspect --format="{{.State.Running}}" ${KAGENT_CONTAINER_ID})
            if [ "${KAGENT_CONTAINER_STATUS_CHECK}" == "false" ]; then
                # KAgent container not running
                log "No ${__KAGENT_REPO} containers running."
            else
                # KAgent container running
                log "${__KAGENT_REPO} container running."
                KAGENT_CONTAINER_RUNNING=1
            fi
        fi
        log
    fi

    pretty_header "Kinetica" 4
    if [ "$(docker images -q "${__KINETICA_REPO}" 2> /dev/null)" == "" ]; then
        # Kinetica image does not exist
        log "ERROR: No images found for ${__KINETICA_REPO} repository. Try building first."
        exit 1
    else
        # Kinetica images does exist; check to see if any started Kinetica containers
        KINETICA_CONTAINER_RUNNING=0
        KINETICA_CONTAINER_IDS=$(docker ps -a | egrep -i "${__KINETICA_REPO}" | awk '{print $1}')
        if [ "${KINETICA_CONTAINER_IDS}" == "" ]; then
            log "No ${__KINETICA_REPO} container(s) started."
        else
            for id in $KINETICA_CONTAINER_IDS
            do
                KINETICA_CONTAINER_STATUS_CHECK=$(docker inspect --format="{{.State.Running}}" ${id})
                if [ "${KINETICA_CONTAINER_STATUS_CHECK}" == "false" ]; then
                    log "At least one ${__KINETICA_REPO} container not running."
                else
                    KINETICA_CONTAINER_RUNNING=1
                fi
            done
            if [ $KINETICA_CONTAINER_RUNNING -eq 1 ]; then
                log "${__KINETICA_REPO} containers running."
            fi
        fi
        log
    fi

    pretty_header "Conclusion" 4
    KAGENT_CONTAINER_STATUS=$(docker ps -a | egrep -i "${__KAGENT_REPO}")
    KINETICA_CONTAINER_STATUS=$(docker ps -a | egrep -i "${__KINETICA_REPO}")
    if [ $KAGENT_CONTAINER_RUNNING -eq 0 ] && [ $KINETICA_CONTAINER_RUNNING -eq 0 ]; then
        # If both the KAgent container and at least one Kinetica container are not running...
        if [ $__UP_DOWN == "down" ]; then
            log "KAgent and/or Kinetica container(s) already stopped; try starting first (up.sh)."
            log
            exit 1
        else
            log "No containers running; primed for start-up."
            log
        fi
    elif [ $KAGENT_CONTAINER_RUNNING -eq 1 ] && [ $KINETICA_CONTAINER_RUNNING -eq 0 ]; then
        # If the KAgent container is running AND at least one Kinetica container is NOT running...
        log "ERROR: KAgent container (${KAGENT_CONTAINER_ID}) running but Kinetica container(s) are not. Please manually stop the KAgent container first."
        log
        exit 1
    elif [ $KAGENT_CONTAINER_RUNNING -eq 0 ] && [ $KINETICA_CONTAINER_RUNNING -eq 1 ]; then
        # If the KAgent container is NOT running AND at least one Kinetica container is running...
        log "ERROR: KAgent container (${KAGENT_CONTAINER_ID}) NOT running but Kinetica container(s) ARE. Please manually stop the Kinetica container(s) first."
        log
        exit 1
    elif [ $KAGENT_CONTAINER_RUNNING -eq 1 ] && [ $KINETICA_CONTAINER_RUNNING -eq 1 ]; then
        # If both the KAgent container and at least one Kinetica container ARE running...
        if [ $__UP_DOWN == "up" ]; then
            log "KAgent and/or Kinetica container(s) already started; try stopping first (down.sh)."
            log $KAGENT_CONTAINER_STATUS && log && log $KINETICA_CONTAINER_STATUS
            exit 1
        else
            log "KAgent and Kinetica containers running; primed for take-down or install."
            log
        fi
    else
        log "ERROR: KAgent and/or Kinetica container status not able to be determined. Please check status with 'docker ps -a'."
        log
        exit 1
    fi

}

# ---------------------------------------------------------------------------
# Config validation

function config_validation
{

    ############################################################################
    #
    # This function uses the given arguments to determine if the specified
    # config file is available.
    #
    # The available arguments are as follows:
    #
    # * CONFIG        : Filepath to the Docker Deploy config file
    #
    ############################################################################

    local __CONFIG=$1

    pretty_header "Configuration Validation" 2

    if [ -e $__CONFIG ]; then
        log "Config file '$__CONFIG' is available!"
        
        # Set CONFIG_FILE env var for config-utils
        run_cmd "export CONFIG_FILE=$__CONFIG"
        export CONFIG_FILE=$__CONFIG
        log

        # Validate the file
        log "Validating file -- this may take a while..."
        validate_config_file "IS_VALID"
        if [ $IS_VALID -eq 0 ]; then
            log "ERROR: Provided config file is invalid; please fix the listed errors above and try again."
            exit 1
        fi
    else
        log "ERROR: Provided config file '$__CONFIG' does not exist. Please run the script again with a file specified."
        exit 1
    fi
    log

}

# ---------------------------------------------------------------------------
# Logging setup

function log_setup
{

    ############################################################################
    #
    # This function uses the given arguments to setup logging for the script
    # calling this function.
    #
    # The available arguments are as follows:
    #
    # * LOG_DIR       : Directory that hosts the logs
    # * LOG_FILE      : Filename for the log
    #
    ############################################################################

    ############################################################################
    #
    # NOTE: This function by its very nature CANNOT use 'run_cmd' and 'log'
    #
    ############################################################################

    local __LOG_DIR=$1
    local __LOG_FILE=$2

    if [ -d "$__LOG_DIR" ]; then
        # echo "Directory '$__LOG_DIR' exists!"
        :
    else
        # echo "Directory '$__LOG_DIR' does not exist!"
        mkdir $__LOG_DIR
    fi

}