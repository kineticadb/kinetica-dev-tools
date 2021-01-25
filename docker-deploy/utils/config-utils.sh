#!/usr/bin/env bash

##############################################################################
#  This script parses the JSON file that contains all the
#  test environment configurations.
#
#  Need to declare the variable $CONFIG_FILE before calling this the
#  functions in this helper script.
##############################################################################


SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# Get the relative path to the root project directory
ROOT_DIR="$SCRIPT_DIR/.."
# Get the absolute value for the root directory
ROOT_DIR_ABS="$(dirname "${SCRIPT_DIR/..}")"


##############################################################################
#  Constants used in the script
##############################################################################
# Configuration File Related Constants
# ####################################
# Docker related constants
KEY_DOCKER="docker"
KEY_PROJECT_NAME="project-name"
KEY_COMPOSE_CONFIG="compose-config"
KEY_KAGENT_DOCKERFILE="kagent-dockerfile"
KEY_KINETICA_DOCKERFILE="kinetica-dockerfile"
KEY_MOUNT_BASE_DIRECTORY="mount-base-directory"
KEY_KAGENT_IMAGE_NAME="kagent-image-name"
KEY_KINETICA_IMAGE_NAME="kinetica-image-name"
KEY_NETWORK_NAME="network-name"
KEY_SUBNET="subnet"
# KAgent specific constants
KEY_KAGENT="kagent"
# Provision related constants
KEY_PROVISION="provision"
KEY_KINETICA_VERSION="kinetica-version"
KEY_LICENSE_KEY="license-key"
KEY_ADMIN_PASSWORD="admin-password"
KEY_DEPLOY="deploy"
KEY_CLOUD_PARAMETERS="cloud-parameters"
KEY_LOCAL_SSH_KEY_DIR="local-ssh-key-directory"
KEY_KAGENT_SSH_KEYS_DIR="kagent-ssh-keys-directory"
KEY_SUDO_PASSWORD="sudo-password"
KEY_ON_PREM="on-prem"
KEY_SSHD_SETUP_SCRIPT="sshd-setup-script"
KEY_SSH_USER="ssh-user"
KEY_SSH_PASSWORD="ssh-password"
# Ring related constants
KEY_RINGS="rings"
KEY_RING_NAME="ring-name"
KEY_CLUSTERS="clusters"
KEY_CLUSTER_NAME="cluster-name"
KEY_ENABLE_HA="enable-ha"
KEY_ENABLE_NP1="enable-np1"
KEY_NODES="nodes"
KEY_HOSTNAME="hostname"
KEY_ROLES="roles"
# Common across multiple sections
KEY_IP_ADDR="ip-address"

# Constants Related to yq
# #######################
YQ_TERM_ARRAY="\"array\""
YQ_TERM_OBJECT="\"object\""

# Constants Used In This Script Internally
# ########################################
RESULT_IS_VALID=1
RESULT_IS_INVALID=0
TRUE="true"
FALSE="false"

# ##################################################################
#
#                  Validation Related Functions
#
# ##################################################################


##############################################################################
#  Helper function that validate that the given JSON snippet has the given
#  keys.  Note that since the first argument is a JSON string and the second
#  argument is an array, this function needs to be called in a very specific
#  way:
#
#      validate_keys_in_json "${JSON}" ${KEYS_ARRAY[@]} "OUTPUT_ARG_NAME"
#
#  where the array KEYS_ARRAY needs to be declared as such:
#
#      KEYS_ARRAY=( "first_key" "second_key" "thrid_key" )
#
#
#  Arguments:
#  * 1st arg -- the JSON snippet to validate
#  * 2nd arg -- the keys to check against; type is an array (of strings)
#  * 3rd arg -- the name of the variable in which the result will be stored
#
#  Returns:
#      1 if valid, 0 if invalid
##############################################################################
function validate_keys_in_json
{
    # Process the input arguments
    # ---------------------------
    # The first argument is a string with possibly spaces in it
    local INPUT_JSON="${1}"
    shift # past the first input argument

    # The expected keys needs to be an array; note that this syntax slurps
    # in the last argument which we will need to extract
    local EXPECTED_KEYS=("${@}")

    # Extract the last argument which is the output argument name
    local OUTPUT_VAR_NAME="${EXPECTED_KEYS[-1]}"
    # Delete the last element (output arg name) from the keys arg
    unset 'EXPECTED_KEYS[-1]'

    # Need to have the # of keys for validation logic
    local EXPECTED_NUM_KEYS=${#EXPECTED_KEYS[@]}
    if [ $EXPECTED_NUM_KEYS -eq 0 ]; then
        log "validate_keys_in_json(): Need to give a non-empty array; got an empty one!"
        exit 1
    fi

    # Also need to have the keys in a JSON array for yq
    # -------------------------------------------------
    # The first element
    local EXPECTED_KEYS_JSON="\"${EXPECTED_KEYS[0]}\""
    # From the second entry onward, concatenate by joining with a comma
    for _KEY in "${EXPECTED_KEYS[@]:1}"; do
        EXPECTED_KEYS_JSON="$EXPECTED_KEYS_JSON,\"$_KEY\""
    done
    EXPECTED_KEYS_JSON="[$EXPECTED_KEYS_JSON]"

    # Check that the given JSON is an object
    local CONTENT_TYPE=$(echo "$INPUT_JSON" | yq 'type')
    if [ $CONTENT_TYPE != $YQ_TERM_OBJECT ]; then
        log "ERROR: validate_keys_in_json(): The given JSON is NOT an object!"

        # Store the result before returning
        local RESULT=$RESULT_IS_INVALID
        eval "$OUTPUT_VAR_NAME='$RESULT'"
        return
    fi

    # Validate that the # of keys in the JSON is correct
    local NUM_KEYS=$(echo "$INPUT_JSON" | yq 'length')
    if [ $NUM_KEYS -gt $EXPECTED_NUM_KEYS ]; then
        log "ERROR: validate_keys_in_json(): The given JSON has the wrong number of keys ($NUM_KEYS), expected $EXPECTED_NUM_KEYS!"

        # Store the result before returning
        local RESULT=$RESULT_IS_INVALID
        eval "$OUTPUT_VAR_NAME='$RESULT'"
        return
    fi

    # Validate the actual keys are present, and nothing more/else is.
    # Note that we need to use both the 'contains' and 'inside' yq filters
    # because yq checks for substring matching.  So, contains would return
    # true if we had a top level key "dockersez", matching it with "docker".
    # The inside filter finds out that "dockersez" is NOT a substring of
    # "docker" and therfore would return false.
    local ARE_VALID_KEYS_CONTAINED=$(echo "$INPUT_JSON" | yq "keys | contains($EXPECTED_KEYS_JSON)")
    local ARE_VALID_KEYS_INSIDE=$(echo "$INPUT_JSON" | yq "keys | inside($EXPECTED_KEYS_JSON)")
    if [ $ARE_VALID_KEYS_CONTAINED == $FALSE ] || [ $ARE_VALID_KEYS_INSIDE == $FALSE ]; then
        # The exact set of keys do not match the top level keys
        local FOUND_KEYS=$(echo "$INPUT_JSON" | yq 'keys')
        log "ERROR: validate_keys_in_json(): The given JSON has the wrong set of keys (has $FOUND_KEYS, expected $EXPECTED_KEYS_JSON)!"

        # Store the result before returning
        local RESULT=$RESULT_IS_INVALID
        eval "$OUTPUT_VAR_NAME='$RESULT'"
        return
    fi

    # Save the fact that the given JSON was validated in the output variable
    local RESULT=$RESULT_IS_VALID
    eval "$OUTPUT_VAR_NAME='$RESULT'"
} # end validate_keys_in_json




##############################################################################
#  Validate that the config file has the proper top level keys.
#
#  Arguments:
#  * first arg -- the name of the variable in which the result will be stored
#
#  Returns:
#      1 if valid, 0 if invalid
##############################################################################
function validate_top_level_keys
{
    local OUTPUT_VAR_NAME="$1"

    # We expect only four top level keys
    local VALID_TOP_KEYS=( $KEY_DOCKER
                           $KEY_KAGENT
                           $KEY_PROVISION
                           $KEY_RINGS)

    # Validate the entire content of the config file
    JSON="$(yq '.' $CONFIG_FILE)"

    # Call the helper validation function; store the result in a local variable
    validate_keys_in_json "${JSON}" ${VALID_TOP_KEYS[@]} "LOCAL_RESULT"

    # Need to save the result in the final output argument
    eval "$OUTPUT_VAR_NAME='$LOCAL_RESULT'"
} # end validate_top_level_keys



##############################################################################
#  Validate that the config file has the proper keys for docker
#  configurations.
#
#  Arguments:
#  * first arg -- the name of the variable in which the result will be stored
#
#  Returns:
#      1 if valid, 0 if invalid
##############################################################################
function validate_docker_keys
{
    local OUTPUT_VAR_NAME="$1"

    # We expect nine keys
    local VALID_KEYS=( $KEY_PROJECT_NAME
                       $KEY_COMPOSE_CONFIG
                       $KEY_KAGENT_DOCKERFILE
                       $KEY_KINETICA_DOCKERFILE
                       $KEY_MOUNT_BASE_DIRECTORY
                       $KEY_KAGENT_IMAGE_NAME
                       $KEY_KINETICA_IMAGE_NAME
                       $KEY_NETWORK_NAME
                       $KEY_SUBNET )

    # Grab just the 'docker' configuration parameters
    JSON="$(yq ".$KEY_DOCKER" $CONFIG_FILE)"

    # Call the helper validation function; store the result in a local variable
    validate_keys_in_json "${JSON}" ${VALID_KEYS[@]} "LOCAL_RESULT"

    # Need to save the result in the final output argument
    eval "$OUTPUT_VAR_NAME='$LOCAL_RESULT'"
} # end validate_docker_keys



##############################################################################
#  Validate that the config file has the proper keys for KAgent
#  configurations.
#
#  Arguments:
#  * first arg -- the name of the variable in which the result will be stored
#
#  Returns:
#      1 if valid, 0 if invalid
##############################################################################
function validate_kagent_keys
{
    local OUTPUT_VAR_NAME="$1"

    # We expect just the one key
    local VALID_KEYS=( $KEY_IP_ADDR )

    # Grab just the 'kagent' configuration parameters
    JSON="$(yq ".$KEY_KAGENT" $CONFIG_FILE)"

    # Call the helper validation function; store the result in a local variable
    validate_keys_in_json "${JSON}" ${VALID_KEYS[@]} "LOCAL_RESULT"

    # Need to save the result in the final output argument
    eval "$OUTPUT_VAR_NAME='$LOCAL_RESULT'"
} # end validate_kagent_keys



##############################################################################
#  Validate that the KAgent section in the config file has the correct syntax.
#  The function checks that it has the correct keys and that the docker
#  container containing KAgent has a unique IP address.
#
#  Arguments:
#  * first arg -- the name of the variable in which the result will be stored
#
#  Returns:
#      1 if valid, 0 if invalid
##############################################################################
function validate_kagent_section
{
    local OUTPUT_VAR_NAME="$1"


    # Note that we will return at the first issue encountered.  Some later
    # validation logic might be dependent on earlier validation.  For example,
    # if a top level key is missing, then validation logic for that section
    # would not work.

    # Validate the provision section keys
    validate_provision_keys "IS_VALID"
    if [ $IS_VALID -eq 0 ]; then
        log "validate_kagent_section(): The kagent keys are invalid in the config file!"
        # Need to save the result in the final output argument
        eval "$OUTPUT_VAR_NAME=$IS_VALID"
        return
    fi


    # Check that this container has a unique IP address
    get_param_value_from_section  "$KEY_KAGENT" "$KEY_IP_ADDR" "KAGENT_IP"
    # If no list of docker container IP addresses has been declared, create one
    if [ ${#ALL_DOCKER_CONTAINER_IPS[@]} -eq 0 ]; then
        # Note that this variable will be a global variable so that other
        # functions like validate_node() can utilize the information
        ALL_DOCKER_CONTAINER_IPS=("$KAGENT_IP")
    else
        # Check the list of node IP addresses already encountered to see if this new
        # one is unique or a duplicate
        for IP in ${ALL_DOCKER_CONTAINER_IPS[@]}; do
            if [[ "$IP" == "$KAGENT_IP" ]]; then
                # Found a duplicate!
                log "ERROR: validate_kagent_section(): KAgent IP address '$KAGENT_IP' must be unique; already exists elsewhere in the config file!"
                # Need to save the result in the final output argument
                local RESULT=$RESULT_IS_INVALID
                eval "$OUTPUT_VAR_NAME='$RESULT'"
                return
            fi
        done

        # This node hostname was not found; add it to the list of node hostnames.
        ALL_DOCKER_CONTAINER_IPS+=("$KAGENT_IP")
    fi

    # Need to save the result in the final output argument
    eval "$OUTPUT_VAR_NAME='$LOCAL_RESULT'"
} # end validate_kagent_section



##############################################################################
#  Validate that the config file has the proper keys for provisioning related
#  configurations.  Note that it does not validate internal structures of each
#  key.
#
#  Arguments:
#  * first arg -- the name of the variable in which the result will be stored
#
#  Returns:
#      1 if valid, 0 if invalid
##############################################################################
function validate_provision_keys
{
    local OUTPUT_VAR_NAME="$1"

    # We expect just the four keys
    # TODO: Decide if the cloud parameters should be optional.
    local VALID_KEYS=( $KEY_KINETICA_VERSION
                       $KEY_LICENSE_KEY
                       $KEY_ADMIN_PASSWORD
                       $KEY_DEPLOY
                       $KEY_CLOUD_PARAMETERS
                       $KEY_ON_PREM )

    # Grab just the 'provision' configuration parameters
    JSON="$(yq ".$KEY_PROVISION" $CONFIG_FILE)"

    # Call the helper validation function; store the result in a local variable
    validate_keys_in_json "${JSON}" ${VALID_KEYS[@]} "LOCAL_RESULT"

    # Need to save the result in the final output argument
    eval "$OUTPUT_VAR_NAME='$LOCAL_RESULT'"
} # end validate_provision_keys



##############################################################################
#  Validate that the config file has the proper keys for the
#  'cloud-parameters' section in the 'provision' configurations.  We are making
#  all the keys required; if the user doesn't need to use a key, just leave
#  the value as an empty string.
#
#  Arguments:
#  * first arg -- the name of the variable in which the result will be stored
#
#  Returns:
#      1 if valid, 0 if invalid
##############################################################################
function validate_provision_cloud_parameters
{
    local OUTPUT_VAR_NAME="$1"

    get_param_value_from_section  "$KEY_PROVISION" "$KEY_CLOUD_PARAMETERS" "CLOUD_PARAMS_JSON"

    # We expect just the three keys
    local VALID_KEYS=( $KEY_LOCAL_SSH_KEY_DIR
                       $KEY_KAGENT_SSH_KEYS_DIR
                       $KEY_SUDO_PASSWORD )

    # Call the helper validation function; store the result in a local variable
    validate_keys_in_json "${CLOUD_PARAMS_JSON}" ${VALID_KEYS[@]} "LOCAL_RESULT"

    # Need to save the result in the final output argument
    eval "$OUTPUT_VAR_NAME='$LOCAL_RESULT'"
} # end validate_provision_cloud_parameters



##############################################################################
#  Validate that the config file has the proper keys for the
#  'on-prem' section in the 'provision' configurations.  We are making
#  all the keys required; if the user doesn't need to use a key, just leave
#  the value as an empty string.
#
#  Arguments:
#  * first arg -- the name of the variable in which the result will be stored
#
#  Returns:
#      1 if valid, 0 if invalid
##############################################################################
function validate_provision_on_prem_parameters
{
    local OUTPUT_VAR_NAME="$1"

    get_param_value_from_section  "$KEY_PROVISION" "$KEY_ON_PREM" "ON_PREM_JSON"

    # We expect just the three keys
    local VALID_KEYS=( $KEY_SSHD_SETUP_SCRIPT
                       $KEY_SSH_USER
                       $KEY_SSH_PASSWORD )

    # Call the helper validation function; store the result in a local variable
    validate_keys_in_json "${ON_PREM_JSON}" ${VALID_KEYS[@]} "LOCAL_RESULT"

    # Need to save the result in the final output argument
    eval "$OUTPUT_VAR_NAME='$LOCAL_RESULT'"
} # end validate_provision_on_prem_parameters


##############################################################################
#  Validate that the provision section of the config file (that it has the
#  correct syntax, with all the required keys).
#
#  Arguments:
#  * first arg -- the name of the variable in which the result will be stored
#
#  Returns:
#      1 if valid, 0 if invalid
##############################################################################
function validate_provision_section
{
    local OUTPUT_VAR_NAME="$1"

    # Note that we will return at the first issue encountered.  Some later
    # validation logic might be dependent on earlier validation.  For example,
    # if a top level key is missing, then validation logic for that section
    # would not work.

    # Validate the provision section keys
    validate_provision_keys "IS_VALID"
    if [ $IS_VALID -eq 0 ]; then
        log "validate_provision_section(): The provision keys are invalid in the config file!"
        # Need to save the result in the final output argument
        eval "$OUTPUT_VAR_NAME=$IS_VALID"
        return
    fi

    # Validate the cloud-parameter keys
    validate_provision_cloud_parameters "IS_VALID"
    if [ $IS_VALID -eq 0 ]; then
        log "validate_provision_section(): The provision cloud parameters section is invalid in the config file!"
        # Need to save the result in the final output argument
        eval "$OUTPUT_VAR_NAME=$IS_VALID"
        return
    fi

    # Validate the on-prem keys
    validate_provision_on_prem_parameters "IS_VALID"
    if [ $IS_VALID -eq 0 ]; then
        log "validate_provision_section(): The provision on-prem section is invalid in the config file!"
        # Need to save the result in the final output argument
        eval "$OUTPUT_VAR_NAME=$IS_VALID"
        return
    fi

    # Need to save the result in the final output argument (section is valid)
    local RESULT=$RESULT_IS_VALID
    eval "$OUTPUT_VAR_NAME=$RESULT"
} # end validate_provision_section



##############################################################################
#  Validate the given node section (that it has the required keys).
#
#  Arguments:
#  * 1st arg -- the index of the ring
#  * 2nd arg -- the index of the cluster
#  * 3rd arg -- the index of the node
#  * 4th arg -- the name of the variable in which the result will be stored
#
#  Returns:
#      1 if valid, 0 if invalid
##############################################################################
function validate_node
{
    local RING_INDEX="$1"
    local CLUSTER_INDEX="$2"
    local NODE_INDEX="$3"
    local OUTPUT_VAR_NAME="$4"

    # Get the entire section for this ring
    get_node_info_by_indices "$RING_INDEX" "$CLUSTER_INDEX" "$NODE_INDEX" "NODE_INFO_JSON"

    # We expect just the three keys
    local VALID_KEYS=( $KEY_HOSTNAME
                       $KEY_ROLES
                       $KEY_IP_ADDR )

    # Call the helper validation function; store the result in a local variable
    validate_keys_in_json "${NODE_INFO_JSON}" ${VALID_KEYS[@]} "IS_VALID"
    if [ $IS_VALID -eq 0 ]; then
        log "ERROR: validate_node(): Keys are invalid for the node section!"
        # Need to save the result in the final output argument
        eval "$OUTPUT_VAR_NAME=$IS_VALID"
        return
    fi

    # Check that this node has a unique hostname (so far)
    get_param_value_from_json "$NODE_INFO_JSON" "$KEY_HOSTNAME" "NODE_HOSTNAME"
    # If no list of node hostnames has been declared, create one
    if [ ${#ALL_NODE_HOSTNAMES[@]} -eq 0 ]; then
        # Note that this variable will be a global variable so that different
        # invocations of this function can utilize it
        ALL_NODE_HOSTNAMES=("$NODE_HOSTNAME")
    else
        # Check the list of node hostnames already encountered to see if this new
        # one is unique or a duplicate
        for HNAME in ${ALL_NODE_HOSTNAMES[@]}; do
            if [[ "$HNAME" == "$NODE_HOSTNAME" ]]; then
                # Found a duplicate!
                log "ERROR: validate_ring(): Node hostname '$NODE_HOSTNAME' must be unique; already exists in prior rings/clusters!"
                # Need to save the result in the final output argument
                local RESULT=$RESULT_IS_INVALID
                eval "$OUTPUT_VAR_NAME='$RESULT'"
                return
            fi
        done

        # This node hostname was not found; add it to the list of node hostnames.
        ALL_NODE_HOSTNAMES+=("$NODE_HOSTNAME")
    fi

    # Check that this node has a unique IP address (so far)
    get_param_value_from_json "$NODE_INFO_JSON" "$KEY_IP_ADDR" "NODE_IP"
    # If no list of node IP addresses has been declared, create one
    if [ ${#ALL_DOCKER_CONTAINER_IPS[@]} -eq 0 ]; then
        # Note that this variable will be a global variable so that different
        # invocations of this function can utilize it
        ALL_DOCKER_CONTAINER_IPS=("$NODE_IP")
    else
        # Check the list of node IP addresses already encountered to see if this new
        # one is unique or a duplicate
        for IP in ${ALL_DOCKER_CONTAINER_IPS[@]}; do
            if [[ "$IP" == "$NODE_IP" ]]; then
                # Found a duplicate!
                log "ERROR: validate_node(): Node IP address '$NODE_IP' must be unique; already exists in prior nodes or the kagent section!"
                # Need to save the result in the final output argument
                local RESULT=$RESULT_IS_INVALID
                eval "$OUTPUT_VAR_NAME='$RESULT'"
                return
            fi
        done

        # This node hostname was not found; add it to the list of node hostnames.
        ALL_DOCKER_CONTAINER_IPS+=("$NODE_IP")
    fi

    # Need to save the result in the final output argument (section is valid)
    local RESULT=$RESULT_IS_VALID
    eval "$OUTPUT_VAR_NAME=$RESULT"
} # end validate_node



##############################################################################
#  Validate the given cluster section.  Will check the keys, the N+1 enabled
#  value (it has to be true/false only), and the nodes, recursively.
#
#  Arguments:
#  * 1st arg -- the index of the ring
#  * 2nd arg -- the index of the cluster
#  * 3rd arg -- the name of the variable in which the result will be stored
#
#  Returns:
#      1 if valid, 0 if invalid
##############################################################################
function validate_cluster
{
    local RING_INDEX="$1"
    local CLUSTER_INDEX="$2"
    local OUTPUT_VAR_NAME="$3"

    # Get the entire section for this ring
    get_cluster_info_by_indices "$RING_INDEX" "$CLUSTER_INDEX" "CLUSTER_INFO_JSON"

    # We expect just the three keys
    local VALID_KEYS=( $KEY_CLUSTER_NAME
                       $KEY_ENABLE_NP1
                       $KEY_NODES )

    # Call the helper validation function; store the result in a local variable
    validate_keys_in_json "${CLUSTER_INFO_JSON}" ${VALID_KEYS[@]} "IS_VALID"
    if [ $IS_VALID -eq 0 ]; then
        log "ERROR: validate_cluster(): Keys are invalid for the cluster section!"
        # Need to save the result in the final output argument
        eval "$OUTPUT_VAR_NAME=$IS_VALID"
        return
    fi

    # Check that this cluster has a unique name (so far)
    get_param_value_from_json "$CLUSTER_INFO_JSON" "$KEY_CLUSTER_NAME" "CLUSTER_NAME"
    # If no list of cluster names has been declared, create one
    if [ ${#ALL_CLUSTER_NAMES[@]} -eq 0 ]; then
        # Note that this variable will be a global variable so that different
        # invocations of this function can utilize it
        ALL_CLUSTER_NAMES=("$CLUSTER_NAME")
    else
        # Check the list of cluster names already encountered to see if this new
        # one is unique or a duplicate
        for CNAME in ${ALL_CLUSTER_NAMES[@]}; do
            if [[ "$CNAME" == "$CLUSTER_NAME" ]]; then
                # Found a duplicate!
                log "ERROR: validate_cluster(): Cluster name '$CLUSTER_NAME' must be unique; already exists in prior rings/clusters!"
                # Need to save the result in the final output argument
                local RESULT=$RESULT_IS_INVALID
                eval "$OUTPUT_VAR_NAME='$RESULT'"
                return
            fi
        done

        # This cluster name was not found; add it to the list of cluster names.
        ALL_CLUSTER_NAMES+=("$CLUSTER_NAME")
    fi

    # Check that the N+1 enabled value is true or false, and nothing else
    get_param_value_from_json "$CLUSTER_INFO_JSON" "$KEY_ENABLE_NP1" "ENABLE_NP1"
    if [ "$ENABLE_NP1" != "$TRUE" ] && [ "$ENABLE_NP1" != "$FALSE" ]; then
        log "ERROR: validate_cluster(): Value of key '$KEY_ENABLE_NP1' must be '$TRUE' or '$FALSE'; got '$ENABLE_NP1'!"
        # Need to save the result in the final output argument
        local RESULT=$RESULT_IS_INVALID
        eval "$OUTPUT_VAR_NAME='$RESULT'"
        return
    fi

    # Check that the nodes sections is an array
    get_param_value_from_json "$CLUSTER_INFO_JSON" "$KEY_NODES" "NODES_JSON"
    local CONTENT_TYPE=$(echo "$NODES_JSON" | yq 'type')
    if [ $CONTENT_TYPE != $YQ_TERM_ARRAY ]; then
        log "ERROR: validate_cluster(): Nodes for the given cluster is NOT an array!"

        # Store the result before returning
        local RESULT=$RESULT_IS_INVALID
        eval "$OUTPUT_VAR_NAME='$RESULT'"
        return
    fi

    # Loop over the nodes and ensure that they are valid
    get_num_nodes_by_indices "$RING_INDEX" "$CLUSTER_INDEX" "NUM_NODES"
    for ((NODE_INDEX=0; NODE_INDEX < NUM_NODES ; NODE_INDEX++)); do
        # Check if the node is valid or not
        validate_node "$RING_INDEX" "$CLUSTER_INDEX" "$NODE_INDEX" "IS_NODE_VALID"

        # Check the result
        if [ $IS_NODE_VALID -eq 0 ]; then
            log "ERROR: validate_cluster(): Node with ring index '$RING_INDEX' & cluster index '$CLUSTER_INDEX' is invalid!"
            # Need to save the result in the final output argument
            eval "$OUTPUT_VAR_NAME=$IS_NODE_VALID"
            return
        fi
    done

    # Need to save the result in the final output argument (section is valid)
    local RESULT=$RESULT_IS_VALID
    eval "$OUTPUT_VAR_NAME=$RESULT"
} # end validate_cluster



##############################################################################
#  Validate the given ring section.  Will check the keys, the HA enabled
#  value (it has to be true/false only), and the clusters, recursively.
#
#  Arguments:
#  * 1st arg -- the index of the ring
#  * 2nd arg -- the name of the variable in which the result will be stored
#
#  Returns:
#      1 if valid, 0 if invalid
##############################################################################
function validate_ring
{
    local RING_INDEX="$1"
    local OUTPUT_VAR_NAME="$2"

    # Get the entire section for this ring
    get_ring_info_by_index "$RING_INDEX" "RING_INFO_JSON"

    # We expect just the three keys
    local VALID_KEYS=( $KEY_RING_NAME
                       $KEY_ENABLE_HA
                       $KEY_CLUSTERS )

    # Call the helper validation function; store the result in a local variable
    validate_keys_in_json "${RING_INFO_JSON}" ${VALID_KEYS[@]} "IS_VALID"
    if [ $IS_VALID -eq 0 ]; then
        log "ERROR: validate_ring(): Keys are invalid for the ring section!"
        # Need to save the result in the final output argument
        eval "$OUTPUT_VAR_NAME=$IS_VALID"
        return
    fi

    # Check that this ring has a unique name (so far)
    get_param_value_from_json "$RING_INFO_JSON" "$KEY_RING_NAME" "RING_NAME"
    # If no list of ring names has been declared, create one
    if [ ${#ALL_RING_NAMES[@]} -eq 0 ]; then
        # Note that this variable will be a global variable so that different
        # invocations of this function can utilize it
        ALL_RING_NAMES=("$RING_NAME")
    else
        # Check the list of ring names already encountered to see if this new
        # one is unique or a duplicate
        for RNAME in ${ALL_RING_NAMES[@]}; do
            if [[ "$RNAME" == "$RING_NAME" ]]; then
                # Found a duplicate!
                log "ERROR: validate_ring(): Ring name '$RING_NAME' must be unique; already exists in prior rings!"
                # Need to save the result in the final output argument
                local RESULT=$RESULT_IS_INVALID
                eval "$OUTPUT_VAR_NAME='$RESULT'"
                return
            fi
        done

        # This ring name was not found; add it to the list of ring names.
        ALL_RING_NAMES+=("$RING_NAME")
    fi

    # Check that the ha enabled value is true or false, and nothing else
    get_param_value_from_json "$RING_INFO_JSON" "$KEY_ENABLE_HA" "ENABLE_HA"
    if [ "$ENABLE_HA" != "$TRUE" ] && [ "$ENABLE_HA" != "$FALSE" ]; then
        log "ERROR: validate_ring(): Value of key '$KEY_ENABLE_HA' must be '$TRUE' or '$FALSE'; got '$ENABLE_HA'!"
        # Need to save the result in the final output argument
        local RESULT=$RESULT_IS_INVALID
        eval "$OUTPUT_VAR_NAME='$RESULT'"
        return
    fi

    # Check that the clusters sections is an array
    get_param_value_from_json "$RING_INFO_JSON" "$KEY_CLUSTERS" "CLUSTERS_JSON"
    local CONTENT_TYPE=$(echo "$CLUSTERS_JSON" | yq 'type')
    if [ $CONTENT_TYPE != $YQ_TERM_ARRAY ]; then
        log "ERROR: validate_ring(): Clusters for the given ring is NOT an array!"

        # Store the result before returning
        local RESULT=$RESULT_IS_INVALID
        eval "$OUTPUT_VAR_NAME='$RESULT'"
        return
    fi

    # Loop over the clusters and ensure that they are valid
    get_num_clusters_by_ring_index "$RING_INDEX" "NUM_CLUSTERS"
    for ((CLUSTER_INDEX=0; CLUSTER_INDEX < NUM_CLUSTERS ; CLUSTER_INDEX++)); do
        # Check if the cluster is valid or not
        validate_cluster "$RING_INDEX" "$CLUSTER_INDEX" "IS_CLUSTER_VALID"

        # Check the result
        if [ $IS_CLUSTER_VALID -eq 0 ]; then
            log "ERROR: validate_ring(): Cluster with index '$CLUSTER_INDEX' is invalid!"
            # Need to save the result in the final output argument
            eval "$OUTPUT_VAR_NAME=$IS_CLUSTER_VALID"
            return
        fi
    done

    # Need to save the result in the final output argument (section is valid)
    local RESULT=$RESULT_IS_VALID
    eval "$OUTPUT_VAR_NAME=$RESULT"
} # end validate_ring


##############################################################################
#  Validate the rings section of the config file.  Will check that it is an
#  array of valid rings sections.  Will check the cluster and node validity
#  recursively.
#
#  Arguments:
#  * first arg -- the name of the variable in which the result will be stored
#
#  Returns:
#      1 if valid, 0 if invalid
##############################################################################
function validate_rings_section
{
    local OUTPUT_VAR_NAME="$1"

    # Note that we will return at the first issue encountered.  Some later
    # validation logic might be dependent on earlier validation.  For example,
    # if a top level key is missing, then validation logic for that section
    # would not work.

    # First, get the 'rings' section
    get_section_params  "$KEY_RINGS" "RINGS_JSON"

    # Check that the given JSON is an arrays
    local CONTENT_TYPE=$(echo "$RINGS_JSON" | yq 'type')
    if [ $CONTENT_TYPE != $YQ_TERM_ARRAY ]; then
        log "ERROR: validate_rings_section(): The given JSON is NOT an array!"

        # Store the result before returning
        local RESULT=$RESULT_IS_INVALID
        eval "$OUTPUT_VAR_NAME='$RESULT'"
        return
    fi

    # Iterate over each ring object to validate it
    get_num_rings "NUM_RINGS"
    for ((RING_INDEX=0; RING_INDEX < NUM_RINGS ; RING_INDEX++)); do
        # Check if the ring is valid or not
        validate_ring "$RING_INDEX" "IS_RING_VALID"

        # Check the result
        if [ $IS_RING_VALID -eq 0 ]; then
            log "ERROR: validate_rings_section(): Ring with index '$RING_INDEX' is invalid!"
            # Need to save the result in the final output argument
            eval "$OUTPUT_VAR_NAME=$IS_RING_VALID"
            return
        fi
    done

    # Need to save the result in the final output argument (section is valid)
    local RESULT=$RESULT_IS_VALID
    eval "$OUTPUT_VAR_NAME=$RESULT"
} # end validate_rings_section



##############################################################################
#  Validate that the config file has the correct syntax, with all the required
#  information.
#
#  Arguments:
#  * first arg -- the name of the variable in which the result will be stored
#
#  Returns:
#      1 if valid, 0 if invalid
##############################################################################
function validate_config_file
{
    local OUTPUT_VAR_NAME="$1"

    # Note that we will return at the first issue encountered.  Some later
    # validation logic might be dependent on earlier validation.  For example,
    # if a top level key is missing, then validation logic for that section
    # would not work.

    # Check if the file exists
    if [ ! -f "$CONFIG_FILE" ]; then
        log "validate_config_file(): File '$CONFIG_FILE' does not exist!"
        # Need to save the result in the final output argument
        eval "$OUTPUT_VAR_NAME=0"
        return
    fi

    # Validate the top level keys
    validate_top_level_keys "IS_VALID"
    if [ $IS_VALID -eq 0 ]; then
        log "validate_config_file(): Top level keys are invalid in the config file!"
        # Need to save the result in the final output argument
        eval "$OUTPUT_VAR_NAME=$IS_VALID"
        return
    fi

    # Validate the docker section keys
    validate_docker_keys "IS_VALID"
    if [ $IS_VALID -eq 0 ]; then
        log "validate_config_file(): The keys are invalid in the docker section of the config file!"
        # Need to save the result in the final output argument
        eval "$OUTPUT_VAR_NAME=$IS_VALID"
        return
    fi

    # Validate the kagent section
    validate_kagent_section "IS_VALID"
    if [ $IS_VALID -eq 0 ]; then
        log "validate_config_file(): The kagent section of the config file is invalid!"
        # Need to save the result in the final output argument
        eval "$OUTPUT_VAR_NAME=$IS_VALID"
        return
    fi

    # Validate the provision section
    validate_provision_section "IS_VALID"
    if [ $IS_VALID -eq 0 ]; then
        log "validate_config_file(): The provision section of the config file is invalid!"
        # Need to save the result in the final output argument
        eval "$OUTPUT_VAR_NAME=$IS_VALID"
        return
    fi

    # Validate the rings section
    validate_rings_section "IS_VALID"
    if [ $IS_VALID -eq 0 ]; then
        log "validate_config_file(): The rings section of the config file is invalid!"
        # Need to save the result in the final output argument
        eval "$OUTPUT_VAR_NAME=$IS_VALID"
        return
    fi

    # Need to save the result in the final output argument (valid)
    local RESULT=$RESULT_IS_VALID
    eval "$OUTPUT_VAR_NAME=$RESULT"
} # end validate_config_file


# ##################################################################
#
#                  Parameter Extraction Functions
#
# ##################################################################


##############################################################################
#  Helper function to extract an entire section from the configuration
#  file.  The returned will likely be a JSON snippet.
#
#  Arguments:
#  * 1st arg -- the top level key (docker, kagent etc.) which to extract
#  * 2nd arg -- the name of the variable in which the result will be stored
#
#  Returns:
#      JSON containing all params for the desired section.
##############################################################################
function get_section_params
{
    local TOP_LEVEL_SECTION_NAME="$1"
    local OUTPUT_VAR_NAME="$2"

    # Grab the desired section from the config file
    local RESULT="$(yq ".$TOP_LEVEL_SECTION_NAME" $CONFIG_FILE)"

    # Check that we actually got the value
    if [ "$RESULT" == "null" ] ; then
        log "get_section_params(): Could not find the section '$TOP_LEVEL_SECTION_NAME'!"
        exit 1
    fi

    # Need to save the result in the final output argument
    eval "$OUTPUT_VAR_NAME='$RESULT'"
} # end get_section_params


##############################################################################
#  Extract the 'docker' section from the configuration file.  The returned
#  will be a JSON snippet containing all the parameters for 'docker'.
#
#  Arguments:
#  * 1st arg -- the name of the variable in which the result will be stored
#
#  Returns:
#      JSON containing all params for the 'docker' section.
##############################################################################
function get_docker_params
{
    local OUTPUT_VAR_NAME="$1"

    # Call the helper section extraction function
    get_section_params "$KEY_DOCKER" "LOCAL_RESULT"

    # Need to save the result in the final output argument
    eval "$OUTPUT_VAR_NAME='$LOCAL_RESULT'"
} # end get_docker_params


##############################################################################
#  Extract the 'kagent' section from the configuration file.  The returned
#  will be a JSON snippet containing all the parameters for 'kagent'.
#
#  Arguments:
#  * 1st arg -- the name of the variable in which the result will be stored
#
#  Returns:
#      JSON containing all params for the 'kagent' section.
##############################################################################
function get_kagent_params
{
    local OUTPUT_VAR_NAME="$1"

    # Call the helper section extraction function
    get_section_params "$KEY_KAGENT" "LOCAL_RESULT"

    # Need to save the result in the final output argument
    eval "$OUTPUT_VAR_NAME='$LOCAL_RESULT'"
} # end get_kagent_params


##############################################################################
#  Extract the 'provision' section from the configuration file.  The returned
#  will be a JSON snippet containing all the parameters for 'provision'.
#
#  Arguments:
#  * 1st arg -- the name of the variable in which the result will be stored
#
#  Returns:
#      JSON containing all params for the 'provision' section.
##############################################################################
function get_provision_params
{
    local OUTPUT_VAR_NAME="$1"

    # Call the helper section extraction function
    get_section_params "$KEY_PROVISION" "LOCAL_RESULT"

    # Need to save the result in the final output argument
    eval "$OUTPUT_VAR_NAME='$LOCAL_RESULT'"
} # end get_provision_params


##############################################################################
#  Extract the 'rings' section from the configuration file.  The returned
#  will be a JSON snippet containing all the parameters for 'rings'.
#
#  Arguments:
#  * 1st arg -- the name of the variable in which the result will be stored
#
#  Returns:
#      JSON containing all params for the 'rings' section.
##############################################################################
function get_rings_params
{
    local OUTPUT_VAR_NAME="$1"

    # Call the helper section extraction function
    get_section_params "$KEY_RINGS" "LOCAL_RESULT"

    # Need to save the result in the final output argument
    eval "$OUTPUT_VAR_NAME='$LOCAL_RESULT'"
} # end get_rings_params


##############################################################################
#  Helper function to extract the desired parameter from the configuration
#  file.  The returned value might be a string containing a single value or
#  a JSON snippet, or a number.
#
#  Note that the 'rings' section doesn't have named parameters inside;
#  it has an array of objects.  So 'rings' is not allowed here.
#
#  Arguments:
#  * 1st arg -- the top level key (docker, kagent etc.) under which the
#               desired param is stored
#  * 2nd arg -- the name of the param to extract
#  * 3rd arg -- the name of the variable in which the result will be stored
#
#  Returns:
#      The value of the desired parameter.  Could be a JSON if it's an object,
#      or a string or number if its a scalar value.
##############################################################################
function get_param_value_from_section
{
    local TOP_LEVEL_SECTION_NAME="$1"
    local PARAM_NAME="$2"
    local OUTPUT_VAR_NAME="$3"

    # Validate that the 'rings' section is not asked for (since it doesn't
    # have named parameters within, but an array)
    if [ "$TOP_LEVEL_SECTION_NAME" == "$KEY_RINGS" ]; then
        log "get_param_value_from_section(): Can't extract named parameters from section '$KEY_RINGS'!"
        exit 1
    fi

    # Grab the desired section from the config file
    local RESULT="$(yq ".$TOP_LEVEL_SECTION_NAME.\"$PARAM_NAME\"" $CONFIG_FILE)"

    # Check that we actually got the value
    if [ "$RESULT" == "null" ] ; then
        log "get_param_value_from_section(): Could not find the given parameter '$PARAM_NAME' from section '$TOP_LEVEL_SECTION_NAME'!"
        exit 1
    fi

    # Need to save the result in the final output argument.  Note the use
    # of single quotes around the result so that the JSON snippets with spaces
    # don't get interpreted by bash as a long command.
    eval "$OUTPUT_VAR_NAME='$RESULT'"
} # end get_param_value_from_section


##############################################################################
#  Helper function to extract the desired parameter from a given JSON snippet.
#  The returned value might be a string containing a single value, a number,
#  or another smaller JSON snippet.
#
#  Arguments:
#  * 1st arg -- a JSON snippet.
#  * 2nd arg -- the name of the param to extract
#  * 3rd arg -- the name of the variable in which the result will be stored
#
#  Returns:
#      The value of the desired parameter.  Could be a JSON if it's an object,
#      or a string or number if its a scalar value.
##############################################################################
function get_param_value_from_json
{
    local INPUT_JSON="$1"
    local PARAM_NAME="$2"
    local OUTPUT_VAR_NAME="$3"

    # Grab the desired section from the config file.
    # Note: Double quoting the parameter name is very important here.  The outer
    #       double quotes allows bash to replace the parameter variable with the
    #       actual parameter name.  But, if that parameter name has a hyphen
    #       in it, then yq fails.  To guard against hyphens, put double quotes
    #       (escaped) surrounding the param name.  It would fail for parameters
    #       like 'ip-address' otherwise.
    local RESULT=$(echo "$INPUT_JSON" | yq ".\"$PARAM_NAME\"")

    # Check that we actually got the value
    if [ "$RESULT" == "null" ] ; then
        log "get_param_value_from_json(): Could not find the given parameter '$PARAM_NAME' within the input JSON snippet!"
        exit 1
    fi

    # Need to save the result in the final output argument
    eval "$OUTPUT_VAR_NAME='$RESULT'"
    # eval "$OUTPUT_VAR_NAME='$RESULT'"
} # end get_param_value_from_json




# ##################################################################
#                  DOCKER RELATED INFORMATION EXTRACTION
# ##################################################################


##############################################################################
#  Get the docker project name.
#
#  Arguments:
#  * 1st arg -- the name of the variable in which the result will be stored
#
#  Returns:
#      The name of the docker project.
##############################################################################
function get_docker_project_name
{
    local OUTPUT_VAR_NAME="$1"

    get_param_value_from_section "$KEY_DOCKER" "$KEY_PROJECT_NAME" "VALUE"

    # Need to save the result in the final output argument.  Note the lack
    # of single quotes around the result so that the caller doesn't get
    # "value" (with the double quotes) as the returned value.
    eval "$OUTPUT_VAR_NAME=$VALUE"
} # end get_docker_project_name

##############################################################################
#  Get the docker compose configuration file name
#
#  Arguments:
#  * 1st arg -- the name of the variable in which the result will be stored
#
#  Returns:
#      The filename of the docker compose configuration file.
##############################################################################
function get_docker_compose_config
{
    local OUTPUT_VAR_NAME="$1"

    get_param_value_from_section "$KEY_DOCKER" "$KEY_COMPOSE_CONFIG" "VALUE"

    # Need to save the result in the final output argument.  Note the lack
    # of single quotes around the result so that the caller doesn't get
    # "value" (with the double quotes) as the returned value.
    eval "$OUTPUT_VAR_NAME=$VALUE"
} # end get_docker_compose_config

##############################################################################
#  Get the name of the dockerfile for the kagent container.
#
#  Arguments:
#  * 1st arg -- the name of the variable in which the result will be stored
#
#  Returns:
#      The name of the dockerfile for the kagent container.
##############################################################################
function get_docker_kagent_dockerfile
{
    local OUTPUT_VAR_NAME="$1"

    get_param_value_from_section "$KEY_DOCKER" "$KEY_KAGENT_DOCKERFILE" "VALUE"

    # Need to save the result in the final output argument.  Note the lack
    # of single quotes around the result so that the caller doesn't get
    # "value" (with the double quotes) as the returned value.
    eval "$OUTPUT_VAR_NAME=$VALUE"
} # end get_docker_kagent_dockerfile


##############################################################################
#  Get the name of the dockerfile for the kinetica container.
#
#  Arguments:
#  * 1st arg -- the name of the variable in which the result will be stored
#
#  Returns:
#      The name of the dockerfile for the kinetica container.
##############################################################################
function get_docker_kinetica_dockerfile
{
    local OUTPUT_VAR_NAME="$1"

    get_param_value_from_section "$KEY_DOCKER" "$KEY_KINETICA_DOCKERFILE" "VALUE"

    # Need to save the result in the final output argument.  Note the lack
    # of single quotes around the result so that the caller doesn't get
    # "value" (with the double quotes) as the returned value.
    eval "$OUTPUT_VAR_NAME=$VALUE"
} # end get_docker_kinetica_dockerfile


##############################################################################
#  Get the mount base directory.  Remove any trialing forward-slash from the
#  path.  Then, prepend the root directory for this project to the mount
#  directory, and get the absolute path to it.
#
#  Arguments:
#  * 1st arg -- the name of the variable in which the result will be stored
#
#  Returns:
#      The absolute path to the base directory for mounting persist
#      directories; no trailing forward-slash.
##############################################################################
function get_docker_mount_base_dir
{
    local OUTPUT_VAR_NAME="$1"

    get_param_value_from_section "$KEY_DOCKER" "$KEY_MOUNT_BASE_DIRECTORY" "VALUE"

    # If the path ends in a forward slash, remove it
    if [[ $VALUE = */ ]]; then
        # Remove the last character
        VALUE=${VALUE%?}
    fi

    # Get the directory name with respect to the root directory
    VALUE="$ROOT_DIR_ABS/$VALUE"

    # Need to save the result in the final output argument.  Note the lack
    # of single quotes around the result so that the caller doesn't get
    # "value" (with the double quotes) as the returned value.
    eval "$OUTPUT_VAR_NAME=$VALUE"
} # end get_docker_mount_base_dir


##############################################################################
#  Get the name of the image name for the kagent container.
#
#  Arguments:
#  * 1st arg -- the name of the variable in which the result will be stored
#
#  Returns:
#      The name of the image name for the kagent container.
##############################################################################
function get_docker_kagent_image_name
{
    local OUTPUT_VAR_NAME="$1"

    get_param_value_from_section "$KEY_DOCKER" "$KEY_KAGENT_IMAGE_NAME" "VALUE"

    # Need to save the result in the final output argument.  Note the lack
    # of single quotes around the result so that the caller doesn't get
    # "value" (with the double quotes) as the returned value.
    eval "$OUTPUT_VAR_NAME=$VALUE"
} # end get_docker_kagent_image_name


##############################################################################
#  Get the name of the image name for the kinetica container.
#
#  Arguments:
#  * 1st arg -- the name of the variable in which the result will be stored
#
#  Returns:
#      The name of the image name for the kinetica container.
##############################################################################
function get_docker_kinetica_image_name
{
    local OUTPUT_VAR_NAME="$1"

    get_param_value_from_section "$KEY_DOCKER" "$KEY_KINETICA_IMAGE_NAME" "VALUE"

    # Need to save the result in the final output argument.  Note the lack
    # of single quotes around the result so that the caller doesn't get
    # "value" (with the double quotes) as the returned value.
    eval "$OUTPUT_VAR_NAME=$VALUE"
} # end get_docker_kinetica_image_name



##############################################################################
#  Get the name of the docker container that docker-compose will use.
#
#  Arguments:
#  * 1st arg -- the name of the variable in which the result will be stored
#
#  Returns:
#      The name of the docker-compose network.
##############################################################################
function get_docker_network_name
{
    local OUTPUT_VAR_NAME="$1"

    get_param_value_from_section "$KEY_DOCKER" "$KEY_NETWORK_NAME" "VALUE"

    # Need to save the result in the final output argument.  Note the lack
    # of single quotes around the result so that the caller doesn't get
    # "value" (with the double quotes) as the returned value.
    eval "$OUTPUT_VAR_NAME=$VALUE"
} # end get_docker_network_name



##############################################################################
#  Get the subnet for the docker network.
#
#  Arguments:
#  * 1st arg -- the name of the variable in which the result will be stored
#
#  Returns:
#      A string containing the subnet for the docker network; will not
#      include quotes around the string.
##############################################################################
function get_docker_subnet
{
    local OUTPUT_VAR_NAME="$1"

    get_param_value_from_section "$KEY_DOCKER" "$KEY_SUBNET" "VALUE"

    # Need to save the result in the final output argument.  Note the lack
    # of single quotes around the result so that the caller doesn't get
    # "value" (with the double quotes) as the returned value.
    eval "$OUTPUT_VAR_NAME=$VALUE"
} # end get_docker_subnet



# ##################################################################
#                 KAGENT RELATED INFORMATION EXTRACTION
# ##################################################################


##############################################################################
#  Get the IP address for the container with kagent installed on it.
#
#  Arguments:
#  * 1st arg -- the name of the variable in which the result will be stored
#
#  Returns:
#      The IP address for the container with kagent installed on it.
##############################################################################
function get_kagent_ip_address
{
    local OUTPUT_VAR_NAME="$1"

    get_param_value_from_section "$KEY_KAGENT" "$KEY_IP_ADDR" "VALUE"

    # Need to save the result in the final output argument.  Note the lack
    # of single quotes around the result so that the caller doesn't get
    # "value" (with the double quotes) as the returned value.
    eval "$OUTPUT_VAR_NAME=$VALUE"
} # end get_kagent_ip_address




# ##################################################################
#              PROVISIONING RELATED INFORMATION EXTRACTION
# ##################################################################


##############################################################################
#  Get the Kinetica version.
#
#  Arguments:
#  * 1st arg -- the name of the variable in which the result will be stored
#
#  Returns:
#      The Kinetica version.
##############################################################################
function get_provision_kinetica_version
{
    local OUTPUT_VAR_NAME="$1"

    get_param_value_from_section "$KEY_PROVISION" "$KEY_KINETICA_VERSION" "VALUE"

    # Need to save the result in the final output argument.  Note the lack
    # of single quotes around the result so that the caller doesn't get
    # "value" (with the double quotes) as the returned value.
    eval "$OUTPUT_VAR_NAME=$VALUE"
} # end get_provision_kinetica_version


##############################################################################
#  Get the Kinetica license key.
#
#  Arguments:
#  * 1st arg -- the name of the variable in which the result will be stored
#
#  Returns:
#      The Kinetica license key.
##############################################################################
function get_provision_kinetica_license
{
    local OUTPUT_VAR_NAME="$1"

    get_param_value_from_section "$KEY_PROVISION" "$KEY_LICENSE_KEY" "VALUE"

    # Need to save the result in the final output argument.  Note the lack
    # of single quotes around the result so that the caller doesn't get
    # "value" (with the double quotes) as the returned value.
    eval "$OUTPUT_VAR_NAME=$VALUE"
} # end get_provision_kinetica_license


##############################################################################
#  Get the admin password.
#
#  Arguments:
#  * 1st arg -- the name of the variable in which the result will be stored
#
#  Returns:
#      The admin password, not quoted.
##############################################################################
function get_provision_admin_password
{
    local OUTPUT_VAR_NAME="$1"

    get_param_value_from_section "$KEY_PROVISION" "$KEY_ADMIN_PASSWORD" "VALUE"

    # Need to save the result in the final output argument.  Note the lack
    # of single quotes around the result so that the caller doesn't get
    # "value" (with the double quotes) as the returned value.
    eval "$OUTPUT_VAR_NAME=$VALUE"
} # end get_provision_admin_password

##############################################################################
#  Get what type of deployment.
#
#  Arguments:
#  * 1st arg -- the name of the variable in which the result will be stored
#
#  Returns:
#      The deployment type
##############################################################################
# is_provision_for_on_prem
function get_provision_deploy
{
    local OUTPUT_VAR_NAME="$1"

    # Need to quote "on-prem" due to the hyphen
    local RESULT="$(yq ".$KEY_PROVISION.$KEY_DEPLOY" $CONFIG_FILE)"
    if [ "$RESULT" == "null" ]; then
        log "ERROR: get_provision_deploy(): No 'deploy' found for provisioning!"
        exit 1
    fi

    # Need to save the result in the final output argument.  Note the lack
    # of single quotes around the result so that the caller doesn't get
    # "value" (with the double quotes) as the returned value.
    eval "$OUTPUT_VAR_NAME=$RESULT"
} # end is_provision_for_on_prem

##############################################################################
#  Get the local SSH key directory from the cloud parameters section.
#
#  Arguments:
#  * 1st arg -- the name of the variable in which the result will be stored
#
#  Returns:
#      The local SSH key directory.
##############################################################################
function get_cloud_params_local_ssh_key_dir
{
    local OUTPUT_VAR_NAME="$1"

    # Need to quote the parameter names in case they have hyphens
    local RESULT="$(yq ".\"$KEY_PROVISION\".\"$KEY_CLOUD_PARAMETERS\".\"$KEY_LOCAL_SSH_KEY_DIR\"" $CONFIG_FILE)"
    if [ "$RESULT" == "null" ]; then
        # TODO: Check if this is a required param; if optional, then we
        #       should NOT throw an error here.
        log "ERROR: get_cloud_params_local_ssh_key_dir(): No SSH key directory found in the cloud parameter section!"
        exit 1
    fi

    # Need to save the result in the final output argument.  Note the lack
    # of single quotes around the result so that the caller doesn't get
    # "value" (with the double quotes) as the returned value.
    eval "$OUTPUT_VAR_NAME=$RESULT"
} # end get_cloud_params_local_ssh_key_dir


##############################################################################
#  Get the kagent SSH keys directory from the cloud parameters section.
#
#  Arguments:
#  * 1st arg -- the name of the variable in which the result will be stored
#
#  Returns:
#      The kagent SSH keys directory.
##############################################################################
function get_cloud_params_kagent_ssh_key_dir
{
    local OUTPUT_VAR_NAME="$1"

    # Need to quote the parameter names in case they have hyphens
    local RESULT="$(yq ".\"$KEY_PROVISION\".\"$KEY_CLOUD_PARAMETERS\".\"$KEY_KAGENT_SSH_KEYS_DIR\"" $CONFIG_FILE)"
    if [ "$RESULT" == "null" ]; then
        # TODO: Check if this is a required param; if optional, then we
        #       should NOT throw an error here.
        log "ERROR: get_cloud_params_kagent_ssh_key_dir(): No KAgent SSH key directory found in the cloud parameter section!"
        exit 1
    fi

    # Need to save the result in the final output argument.  Note the lack
    # of single quotes around the result so that the caller doesn't get
    # "value" (with the double quotes) as the returned value.
    eval "$OUTPUT_VAR_NAME=$RESULT"
} # end get_cloud_params_kagent_ssh_key_dir


##############################################################################
#  Get the OPTIONAL parameter sudo password from the cloud params section.
#
#  Arguments:
#  * 1st arg -- the name of the variable in which the result will be stored
#
#  Returns:
#      The sudo password, if any.  "null" otherwise.
##############################################################################
function get_cloud_params_sudo_password
{
    local OUTPUT_VAR_NAME="$1"

    # Need to quote the parameter names in case they have hyphens
    local RESULT="$(yq ".\"$KEY_PROVISION\".\"$KEY_CLOUD_PARAMETERS\".\"$KEY_SUDO_PASSWORD\"" $CONFIG_FILE)"

    # Need to save the result in the final output argument.  Note the lack
    # of single quotes around the result so that the caller doesn't get
    # "value" (with the double quotes) as the returned value.
    eval "$OUTPUT_VAR_NAME=$RESULT"
} # end get_cloud_params_sudo_password


##############################################################################
#  Get the name for the SSHD setup script for the container(s).
#
#  Arguments:
#  * 1st arg -- the name of the variable in which the result will be stored
#
#  Returns:
#      The filename of the SSHD setup script.
##############################################################################
function get_provision_on_prem_sshd_setup_script
{
    local OUTPUT_VAR_NAME="$1"

    # Need to quote "on-prem" & "ssh-user" due to the hyphens
    local RESULT="$(yq ".$KEY_PROVISION.\"$KEY_ON_PREM\".\"$KEY_SSHD_SETUP_SCRIPT\"" $CONFIG_FILE)"
    if [ "$RESULT" == "null" ]; then
        log "ERROR: get_provision_on_prem_sshd_setup_script(): No SSHD setup script found for 'on-prem' provisioning!"
        exit 1
    fi

    # Need to save the result in the final output argument.  Note the lack
    # of single quotes around the result so that the caller doesn't get
    # "username" (with the double quotes) as the returned value.
    eval "$OUTPUT_VAR_NAME=$RESULT"
} # end get_provision_on_prem_ssh_user


##############################################################################
#  Get the SSH username for on-premise provisioning.
#
#  Arguments:
#  * 1st arg -- the name of the variable in which the result will be stored
#
#  Returns:
#      The SSH username for on-prem provisioning.
##############################################################################
function get_provision_on_prem_ssh_user
{
    local OUTPUT_VAR_NAME="$1"

    # Need to quote "on-prem" & "ssh-user" due to the hyphens
    local RESULT="$(yq ".$KEY_PROVISION.\"$KEY_ON_PREM\".\"$KEY_SSH_USER\"" $CONFIG_FILE)"
    if [ "$RESULT" == "null" ]; then
        log "ERROR: get_provision_on_prem_ssh_user(): No SSH username found for 'on-prem' provisioning!"
        exit 1
    fi

    # Need to save the result in the final output argument.  Note the lack
    # of single quotes around the result so that the caller doesn't get
    # "username" (with the double quotes) as the returned value.
    eval "$OUTPUT_VAR_NAME=$RESULT"
} # end get_provision_on_prem_ssh_user


##############################################################################
#  Get the SSH password for on-premise provisioning.
#
#  Arguments:
#  * 1st arg -- the name of the variable in which the result will be stored
#
#  Returns:
#      The SSH password for on-prem provisioning.
##############################################################################
function get_provision_on_prem_ssh_password
{
    local OUTPUT_VAR_NAME="$1"

    # Need to quote "on-prem" & "ssh-password" due to the hyphens
    local RESULT="$(yq ".$KEY_PROVISION.\"$KEY_ON_PREM\".\"$KEY_SSH_PASSWORD\"" $CONFIG_FILE)"
    if [ "$RESULT" == "null" ]; then
        log "ERROR: get_provision_on_prem_ssh_password(): No SSH password found for 'on-prem' provisioning!"
        exit 1
    fi

    # Need to save the result in the final output argument.  Note the lack
    # of single quotes around the result so that the caller doesn't get
    # "username" (with the double quotes) as the returned value.
    eval "$OUTPUT_VAR_NAME=$RESULT"
} # end get_provision_on_prem_ssh_password





# ##################################################################
#                  RINGS RELATED INFORMATION EXTRACTION
# ##################################################################


##############################################################################
#  Return how many rings are configured.
#
#  Arguments:
#  * 1st arg -- the name of the variable in which the result will be stored
#
#  Returns:
#      Integer indicating the number of configured rings.
##############################################################################
function get_num_rings
{
    local OUTPUT_VAR_NAME="$1"

    # Get the rings information and then get the length of the array
    get_rings_params "RINGS_INFO_JSON"
    local RESULT="$(echo "$RINGS_INFO_JSON" | yq 'length' )"

    # Need to save the result in the final output argument
    eval "$OUTPUT_VAR_NAME='$RESULT'"
} # end get_num_rings


##############################################################################
#  Return the information for the desired ring by index (in the array).
#  Throws an error if the index is out of bounds.
#
#  Arguments:
#  * 1st arg -- the index of the ring which to get
#  * 2nd arg -- the name of the variable in which the result will be stored
#
#  Returns:
#      JSON with all the configuration for the given ring
##############################################################################
function get_ring_info_by_index
{
    local RING_INDEX="$1"
    local OUTPUT_VAR_NAME="$2"

    # Get the information on all the rings
    get_rings_params "RINGS_INFO_JSON"

    # Check that the given index is within the range
    local NUM_RINGS="$(echo "$RINGS_INFO_JSON" | yq 'length' )"
    if [ $RING_INDEX -lt 0 ] || [ $RING_INDEX -ge $NUM_RINGS ]; then
        log "ERROR: get_ring_info_by_index(): Given index $RING_INDEX is out of bounds!"
        exit 1
    fi

    # Get the JSON for the desired ring
    local RESULT=$(echo "$RINGS_INFO_JSON" | yq ".[$RING_INDEX]" )

    # Need to save the result in the final output argument
    eval "$OUTPUT_VAR_NAME='$RESULT'"
} # end get_ring_info_by_index



##############################################################################
#  Return the index for the desired ring by name.  If not found, returns
#  null.
#
#  Arguments:
#  * 1st arg -- the name of the ring whose informatio to retrieve
#  * 2nd arg -- the name of the variable in which the result will be stored
#
#  Returns:
#      Integer containing the index for given ring, or null if not found.
##############################################################################
function get_ring_index_from_name
{
    local RING_NAME="$1"
    local OUTPUT_VAR_NAME="$2"

    # Get the information on all the rings
    get_rings_params "RINGS_INFO_JSON"

    # Get the index for the matching ring (null if not found)
    local RESULT=$(echo "$RINGS_INFO_JSON" \
                       | yq "map(.\"$KEY_RING_NAME\") | index(\"$RING_NAME\")" )

    # Need to save the result in the final output argument
    eval "$OUTPUT_VAR_NAME='$RESULT'"
} # end get_ring_index_from_name



##############################################################################
#  Return the information for the desired ring by name.  Throws an error if
#  no matching ring is found.
#
#  Arguments:
#  * 1st arg -- the name of the ring whose informatio to retrieve
#  * 2nd arg -- the name of the variable in which the result will be stored
#
#  Returns:
#      JSON with all the configuration for the given ring.
##############################################################################
function get_ring_info_by_name
{
    local RING_NAME="$1"
    local OUTPUT_VAR_NAME="$2"

    # Get the index of the ring by name
    get_ring_index_from_name "$RING_NAME" "RING_INDEX"

    # Check that there was a match!
    if [ "$RING_INDEX" == "null" ]; then
        log "ERROR: get_ring_info_by_name(): No match for name $RING_NAME!"
        exit 1
    fi

    # Use the index to get the info
    get_ring_info_by_index "$RING_INDEX" "LOCAL_RESULT"

    # Need to save the result in the final output argument
    eval "$OUTPUT_VAR_NAME='$LOCAL_RESULT'"
} # end get_ring_info_by_name



##############################################################################
#  Get the name of the given ring (by index).  Throws an error if the index
#  is out of bounds.
#
#  Arguments:
#  * 1st arg -- the index of the ring
#  * 2nd arg -- the name of the variable in which the result will be stored
#
#  Returns:
#      The name of the given ring.
##############################################################################
function get_ring_name_by_index
{
    local RING_INDEX="$1"
    local OUTPUT_VAR_NAME="$2"

    # Use the index to get the info (throws an error for out of bounds index)
    get_ring_info_by_index "$RING_INDEX" "RING_INFO_JSON"

    # Get the name of this ring
    local RESULT=$(echo "$RING_INFO_JSON" | yq ".\"$KEY_RING_NAME\"")

    # Need to save the result in the final output argument.  Note the lack
    # of single quotes around the result so that the caller doesn't get
    # "ringname" (with the double quotes) as the returned value.
    eval "$OUTPUT_VAR_NAME=$RESULT"
} # end get_ring_name_by_index


##############################################################################
#  Get whether the ring (given by index) is enabled for HA.  Throws an error
#  if the index is out of bounds.
#
#  Arguments:
#  * 1st arg -- the index of the ring
#  * 2nd arg -- the name of the variable in which the result will be stored
#
#  Returns:
#      Integer value 1 indicating that the ring should be enabled for HA
#      and 0 for not enabling it.
##############################################################################
function is_ring_ha_enabled_by_index
{
    local RING_INDEX="$1"
    local OUTPUT_VAR_NAME="$2"

    # Use the index to get the info (throws an error for out of bounds index)
    get_ring_info_by_index "$RING_INDEX" "RING_INFO_JSON"

    # Get the enable-ha value for this ring
    local VALUE=$(echo "$RING_INFO_JSON" | yq ".\"$KEY_ENABLE_HA\"")

    # Parse the true/false string value to 0 or 1
    local RESULT=0
    if [ $VALUE == $TRUE ]; then
        RESULT=1
    fi

    # Need to save the result in the final output argument
    eval "$OUTPUT_VAR_NAME=$RESULT"
} # end is_ring_ha_enabled_by_index


##############################################################################
#  Get the number of clusters for the given ring (by index).  Throws an error
#  if the index is out of bounds.
#
#  Arguments:
#  * 1st arg -- the index of the ring
#  * 2nd arg -- the name of the variable in which the result will be stored
#
#  Returns:
#      Integer containing the number of clusters for the given ring.
##############################################################################
function get_num_clusters_by_ring_index
{
    local RING_INDEX="$1"
    local OUTPUT_VAR_NAME="$2"

    # Use the index to get the info (throws an error for out of bounds index)
    get_ring_info_by_index "$RING_INDEX" "RING_INFO_JSON"

    # Get the # of clusters for this ring
    local RESULT=$(echo "$RING_INFO_JSON" | yq ".\"$KEY_CLUSTERS\" | length")

    # Need to save the result in the final output argument
    eval "$OUTPUT_VAR_NAME='$RESULT'"
} # end get_num_clusters_by_ring_index


##############################################################################
#  Get the number of clusters for the given ring (by name).  Throws an error
#  if no ring with such a name is found.
#
#  Arguments:
#  * 1st arg -- the name of the ring
#  * 2nd arg -- the name of the variable in which the result will be stored
#
#  Returns:
#      Integer containing the number of clusters for the given ring.
##############################################################################
function get_num_clusters_by_ring_name
{
    local RING_NAME="$1"
    local OUTPUT_VAR_NAME="$2"

    # Use the index to get the info (throws an error for out of bounds index)
    get_ring_info_by_name "$RING_NAME" "RING_INFO_JSON"

    # Get the # of clusters for this ring
    local RESULT=$(echo "$RING_INFO_JSON" | yq ".\"$KEY_CLUSTERS\" | length")

    # Need to save the result in the final output argument
    eval "$OUTPUT_VAR_NAME='$RESULT'"
} # end get_num_clusters_by_ring_name


##############################################################################
#  Get the array of cluster information for the given ring (by index).  Throws
#  an error if the ring index is out of bounds.
#
#  Arguments:
#  * 1st arg -- the index of the ring
#  * 2nd arg -- the name of the variable in which the result will be stored
#
#  Returns:
#      JSON array containing information on all the clusters for the given
#      ring.
##############################################################################
function get_all_clusters_by_ring_index
{
    local RING_INDEX="$1"
    local OUTPUT_VAR_NAME="$2"

    # Use the index to get the info (throws an error for out of bounds index)
    get_ring_info_by_index "$RING_INDEX" "RING_INFO_JSON"

    # Get the # of clusters for this ring
    local RESULT=$(echo "$RING_INFO_JSON" | yq ".\"$KEY_CLUSTERS\"")

    # Need to save the result in the final output argument
    eval "$OUTPUT_VAR_NAME='$RESULT'"
} # end get_all_clusters_by_ring_index


##############################################################################
#  Get the array of cluster information for the given ring (by name).  Throws
#  an error if no such ring is found.
#
#  Arguments:
#  * 1st arg -- the name of the ring
#  * 2nd arg -- the name of the variable in which the result will be stored
#
#  Returns:
#      JSON array containing information on all the clusters for the given
#      ring.
##############################################################################
function get_all_clusters_by_ring_name
{
    local RING_NAME="$1"
    local OUTPUT_VAR_NAME="$2"

    # Get the ring info (throw an error for no such match)
    get_ring_info_by_name "$RING_NAME" "RING_INFO_JSON"

    # Get the array of clusters for this ring
    local RESULT=$(echo "$RING_INFO_JSON" | yq ".\"$KEY_CLUSTERS\"")

    # Need to save the result in the final output argument
    eval "$OUTPUT_VAR_NAME='$RESULT'"
} # end get_all_clusters_by_ring_name


##############################################################################
#  Get all information pertaining to a cluster (by ring and cluster indices).
#  Throws an error if either of the indices are out of bounds.
#
#  Arguments:
#  * 1st arg -- the index of the ring
#  * 2nd arg -- the index of the cluster
#  * 3rd arg -- the name of the variable in which the result will be stored
#
#  Returns:
#      JSON containing all the parameters for the given cluster.
##############################################################################
function get_cluster_info_by_indices
{
    local RING_INDEX="$1"
    local CLUSTER_INDEX="$2"
    local OUTPUT_VAR_NAME="$3"

    # Get the ring info (throws an error for out of bounds ring index)
    get_ring_info_by_index "$RING_INDEX" "RING_INFO_JSON"

    # Get the # of clusters for this ring
    local NUM_CLUSTERS=$(echo "$RING_INFO_JSON" | yq ".\"$KEY_CLUSTERS\" | length")

    # Check that the cluster index is within the range
    if [ $CLUSTER_INDEX -lt 0 ] || [ $CLUSTER_INDEX -ge $NUM_CLUSTERS ]; then
        log "ERROR: get_cluster_info_by_indices(): Given cluster index $CLUSTER_INDEX is out of bounds!"
        exit 1
    fi

    # Get the JSON for the desired cluster
    local RESULT=$(echo "$RING_INFO_JSON" | yq ".\"$KEY_CLUSTERS\" | .[$CLUSTER_INDEX]" )

    # Need to save the result in the final output argument
    eval "$OUTPUT_VAR_NAME='$RESULT'"
} # end get_cluster_info_by_indices




##############################################################################
#  Get all information pertaining to a cluster (by ring and cluster names).
#  Throws an error if no matching ring or cluster is found.
#
#  Arguments:
#  * 1st arg -- the name of the ring
#  * 2nd arg -- the name of the cluster
#  * 3rd arg -- the name of the variable in which the result will be stored
#
#  Returns:
#      JSON containing all the parameters for the given cluster.
##############################################################################
function get_cluster_info_by_names
{
    local RING_NAME="$1"
    local CLUSTER_NAME="$2"
    local OUTPUT_VAR_NAME="$3"

    # Get the array of cluster info (exits if no matching ring is found)
    get_all_clusters_by_ring_name "$RING_NAME" "CLUSTERS_INFO_JSON"

    # Get the index for the desired cluster
    local CLUSTER_INDEX=$(echo "$CLUSTERS_INFO_JSON" | \
                              yq "map(.\"$KEY_CLUSTER_NAME\") | index(\"$CLUSTER_NAME\")" )

    # Check that a matching cluster was found
    if [ "$CLUSTER_INDEX" == "null" ]; then
        log "ERROR: get_cluster_info_by_names(): No matching cluster for name $CLUSTER_NAME was found!"
        exit 1
    fi

    # Get the JSON for the desired cluster
    local RESULT=$(echo "$CLUSTERS_INFO_JSON" | yq ".[$CLUSTER_INDEX]" )

    # Need to save the result in the final output argument
    eval "$OUTPUT_VAR_NAME='$RESULT'"
} # end get_cluster_info_by_names



##############################################################################
#  Get the name of a cluster identified by ring and cluster indices.
#  Throws an error if either of the indices are out of bounds.
#
#  Arguments:
#  * 1st arg -- the index of the ring
#  * 2nd arg -- the index of the cluster
#  * 3rd arg -- the name of the variable in which the result will be stored
#
#  Returns:
#      The name of the given cluster.
##############################################################################
function get_cluster_name_by_indices
{
    local RING_INDEX="$1"
    local CLUSTER_INDEX="$2"
    local OUTPUT_VAR_NAME="$3"

    # Get the cluster info (throws an error for any out of bounds index)
    get_cluster_info_by_indices "$RING_INDEX" "$CLUSTER_INDEX" "CLUSTER_INFO_JSON"

    # Get the name of the cluster
    local RESULT=$(echo "$CLUSTER_INFO_JSON" | yq ".\"$KEY_CLUSTER_NAME\"" )

    # Need to save the result in the final output argument.  Note the lack
    # of single quotes around the result so that the caller doesn't get
    # "ringname" (with the double quotes) as the returned value.
    eval "$OUTPUT_VAR_NAME=$RESULT"
} # end get_cluster_name_by_indices



##############################################################################
#  Get whether the cluster (identified by cluster and ring indices) should be
#  enabled for N+1.  Throws an error if any index is out of bounds.
#
#  Arguments:
#  * 1st arg -- the index of the ring
#  * 2nd arg -- the index of the cluster
#  * 3rd arg -- the name of the variable in which the result will be stored
#
#  Returns:
#      Integer value 1 indicating that the ring should be enabled for N+1
#      and 0 for not enabling it.
##############################################################################
function is_cluster_np1_enabled_by_indices
{
    local RING_INDEX="$1"
    local CLUSTER_INDEX="$2"
    local OUTPUT_VAR_NAME="$3"

    # Get the cluster info (throws an error for any out of bounds index)
    get_cluster_info_by_indices "$RING_INDEX" "$CLUSTER_INDEX" "CLUSTER_INFO_JSON"

    # Get the enable-np1 value for this ring
    local VALUE=$(echo "$CLUSTER_INFO_JSON" | yq ".\"$KEY_ENABLE_NP1\"")

    # Parse the true/false string value to 0 or 1
    local RESULT=0
    if [ $VALUE == $TRUE ]; then
        RESULT=1
    fi

    # Need to save the result in the final output argument
    eval "$OUTPUT_VAR_NAME=$RESULT"
} # end is_cluster_np1_enabled_by_indices



##############################################################################
#  Get the number of nodes for the given cluster (identified by ring and
#  cluster indices).  Throws an error if the index is out of bounds.
#
#  Arguments:
#  * 1st arg -- the index of the ring
#  * 2nd arg -- the index of the cluster
#  * 3rd arg -- the name of the variable in which the result will be stored
#
#  Returns:
#      Integer containing the number of nodes for the given cluster.
##############################################################################
function get_num_nodes_by_indices
{
    local RING_INDEX="$1"
    local CLUSTER_INDEX="$2"
    local OUTPUT_VAR_NAME="$3"

    # Use the index to get the info (throws an error for any out of bounds
    # index)
    get_cluster_info_by_indices "$RING_INDEX" "$CLUSTER_INDEX" "CLUSTER_INFO_JSON"

    # Get the # of nodes for this cluster
    local RESULT=$(echo "$CLUSTER_INFO_JSON" | yq ".\"$KEY_NODES\" | length")

    # Need to save the result in the final output argument
    eval "$OUTPUT_VAR_NAME='$RESULT'"
} # end get_num_nodes_by_indices



##############################################################################
#  Get the number of nodes for the given cluster (identified by ring and
#  cluster names).  Throws an error if such ring or cluster do not exist.
#
#  Arguments:
#  * 1st arg -- the name of the ring
#  * 2nd arg -- the name of the cluster
#  * 3rd arg -- the name of the variable in which the result will be stored
#
#  Returns:
#      Integer containing the number of nodes for the given cluster.
##############################################################################
function get_num_nodes_by_names
{
    local RING_NAME="$1"
    local CLUSTER_NAME="$2"
    local OUTPUT_VAR_NAME="$3"

    # Use the index to get the info (throws an error for non-existing names)
    get_cluster_info_by_names "$RING_NAME" "$CLUSTER_NAME" "CLUSTER_INFO_JSON"

    # Get the # of nodes for this cluster
    local RESULT=$(echo "$CLUSTER_INFO_JSON" | yq ".\"$KEY_NODES\" | length")

    # Need to save the result in the final output argument
    eval "$OUTPUT_VAR_NAME='$RESULT'"
} # end get_num_nodes_by_names


##############################################################################
#  Get the array of node information for the given ring & cluster (by
#  indices).  Throws an error if any of the indices is out of bounds.
#
#  Arguments:
#  * 1st arg -- the index of the ring
#  * 2nd arg -- the index of the cluster
#  * 3rd arg -- the name of the variable in which the result will be stored
#
#  Returns:
#      JSON array containing information on all the nodes for the given
#      cluster.
##############################################################################
function get_all_nodes_by_indices
{
    local RING_INDEX="$1"
    local CLUSTER_INDEX="$2"
    local OUTPUT_VAR_NAME="$3"

    # Use the index to get the cluster info (throws an error for out of bounds
    # index)
    get_cluster_info_by_indices "$RING_INDEX" "$CLUSTER_INDEX" "CLUSTER_INFO_JSON"

    # Get the # of nodes for this cluster
    local RESULT=$(echo "$CLUSTER_INFO_JSON" | yq ".\"$KEY_NODES\"")

    # Need to save the result in the final output argument
    eval "$OUTPUT_VAR_NAME='$RESULT'"
} # end get_all_nodes_by_indices


##############################################################################
#  Get the array of node information for the given cluster (by cluster &
#  ring names).  Throws an error if no such cluster is found.
#
#  Arguments:
#  * 1st arg -- the name of the ring
#  * 2nd arg -- the name of the cluster
#  * 3rd arg -- the name of the variable in which the result will be stored
#
#  Returns:
#      JSON array containing information on all the nodes for the given
#      cluster.
##############################################################################
function get_all_nodes_by_names
{
    local RING_NAME="$1"
    local CLUSTER_NAME="$2"
    local OUTPUT_VAR_NAME="$3"

    # Get the cluster info (throw an error for no such match)
    get_cluster_info_by_names "$RING_NAME" "$CLUSTER_NAME" "CLUSTER_INFO_JSON"

    # Get the array of nodes for this cluster
    local RESULT=$(echo "$CLUSTER_INFO_JSON" | yq ".\"$KEY_NODES\"")

    # Need to save the result in the final output argument
    eval "$OUTPUT_VAR_NAME='$RESULT'"
} # end get_all_nodes_by_names



##############################################################################
#  Get the information of a node identified by ring, cluster, and node
#  indices.  Throws an error if any of the indices are out of bounds.
#
#  Arguments:
#  * 1st arg -- the index of the ring
#  * 2nd arg -- the index of the cluster
#  * 3rd arg -- the index of the node
#  * 4th arg -- the name of the variable in which the result will be stored
#
#  Returns:
#      The JSON snippet containing the node information.
##############################################################################
function get_node_info_by_indices
{
    local RING_INDEX="$1"
    local CLUSTER_INDEX="$2"
    local NODE_INDEX="$3"
    local OUTPUT_VAR_NAME="$4"

    # Get the cluster info (throws an error for any out of bounds index)
    get_cluster_info_by_indices "$RING_INDEX" "$CLUSTER_INDEX" "CLUSTER_INFO_JSON"

    # Get the # of nodes for this ring
    local NUM_NODES=$(echo "$CLUSTER_INFO_JSON" | yq ".\"$KEY_NODES\" | length")

    # Check that the cluster index is within the range
    if [ $NODE_INDEX -lt 0 ] || [ $NODE_INDEX -ge $NUM_NODES ]; then
        log "ERROR: get_node_info_by_indices(): Given node index $NODE_INDEX is out of bounds!"
        exit 1
    fi

    # Get the JSON for the desired node
    local RESULT=$(echo "$CLUSTER_INFO_JSON" | yq ".\"$KEY_NODES\" | .[$NODE_INDEX]" )

    # Need to save the result in the final output argument
    eval "$OUTPUT_VAR_NAME='$RESULT'"
} # end get_node_info_by_indices



##############################################################################
#  Get the information of a node identified by ring & cluster names and node
#  hostname.  Throws an error if any of the names do not exist.
#
#  Arguments:
#  * 1st arg -- the name of the ring
#  * 2nd arg -- the name of the cluster
#  * 3rd arg -- the hostname of the node
#  * 4th arg -- the name of the variable in which the result will be stored
#
#  Returns:
#      The JSON snippet containing the node information.
##############################################################################
function get_node_info_by_names
{
    local RING_NAME="$1"
    local CLUSTER_NAME="$2"
    local NODE_NAME="$3"
    local OUTPUT_VAR_NAME="$4"

    # TODO: Look at get_cluster_info_by_names()
    # Get the array of cluster info (exits if no matching ring is found)
    get_all_nodes_by_names "$RING_NAME" "$CLUSTER_NAME" "NODES_INFO_JSON"

    # Get the index for the desired node
    local NODE_INDEX=$(echo "$NODES_INFO_JSON" | \
                           yq "map(.\"$KEY_HOSTNAME\") | index(\"$NODE_NAME\")" )

    # Check that a matching cluster was found
    if [ "$NODE_INDEX" == "null" ]; then
        log "ERROR: get_node_info_by_names(): No node with hostname $NODE_NAME was found!"
        exit 1
    fi

    # Get the JSON for the desired cluster
    local RESULT=$(echo "$NODES_INFO_JSON" | yq ".[$NODE_INDEX]" )

    # Need to save the result in the final output argument
    eval "$OUTPUT_VAR_NAME='$RESULT'"
} # end get_node_info_by_names



##############################################################################
#  Get the hostname of a node identified by ring, cluster, and node indices.
#  Throws an error if any of the indices are out of bounds.
#
#  Arguments:
#  * 1st arg -- the index of the ring
#  * 2nd arg -- the index of the cluster
#  * 3rd arg -- the index of the node
#  * 4th arg -- the name of the variable in which the result will be stored
#
#  Returns:
#      The hostname of the given node.
##############################################################################
function get_node_hostname_by_indices
{
    local RING_INDEX="$1"
    local CLUSTER_INDEX="$2"
    local NODE_INDEX="$3"
    local OUTPUT_VAR_NAME="$4"

    # Get the node info (throws an error for any out of bounds index)
    get_node_info_by_indices "$RING_INDEX" "$CLUSTER_INDEX" "$NODE_INDEX" "NODE_INFO_JSON"

    # Get the hostname of the node
    local RESULT=$(echo "$NODE_INFO_JSON" | yq ".\"$KEY_HOSTNAME\"" )

    # Need to save the result in the final output argument.  Note the lack
    # of single quotes around the result so that the caller doesn't get
    # "ringname" (with the double quotes) as the returned value.
    eval "$OUTPUT_VAR_NAME=$RESULT"
} # end get_node_hostname_by_indices


##############################################################################
#  Get the IP address of a node identified by ring, cluster, and node indices.
#  Throws an error if any of the indices are out of bounds.
#
#  Arguments:
#  * 1st arg -- the index of the ring
#  * 2nd arg -- the index of the cluster
#  * 3rd arg -- the index of the node
#  * 4th arg -- the name of the variable in which the result will be stored
#
#  Returns:
#      The IP address of the given node.
##############################################################################
function get_node_ip_by_indices
{
    local RING_INDEX="$1"
    local CLUSTER_INDEX="$2"
    local NODE_INDEX="$3"
    local OUTPUT_VAR_NAME="$4"

    # Get the node info (throws an error for any out of bounds index)
    get_node_info_by_indices "$RING_INDEX" "$CLUSTER_INDEX" "$NODE_INDEX" "NODE_INFO_JSON"

    # Get the hostname of the node
    local RESULT=$(echo "$NODE_INFO_JSON" | yq ".\"$KEY_IP_ADDR\"" )

    # Need to save the result in the final output argument.  Note the lack
    # of single quotes around the result so that the caller doesn't get
    # "ringname" (with the double quotes) as the returned value.
    eval "$OUTPUT_VAR_NAME=$RESULT"
} # end get_node_ip_by_indices


##############################################################################
#  Get the roles of a node identified by ring, cluster, and node indices.
#  Throws an error if any of the indices are out of bounds.
#
#  Arguments:
#  * 1st arg -- the index of the ring
#  * 2nd arg -- the index of the cluster
#  * 3rd arg -- the index of the node
#  * 4th arg -- the name of the variable in which the result will be stored
#
#  Returns:
#      The roles of the given node.
##############################################################################
function get_node_roles_by_indices
{
    local RING_INDEX="$1"
    local CLUSTER_INDEX="$2"
    local NODE_INDEX="$3"
    local OUTPUT_VAR_NAME="$4"

    # Get the node info (throws an error for any out of bounds index)
    get_node_info_by_indices "$RING_INDEX" "$CLUSTER_INDEX" "$NODE_INDEX" "NODE_INFO_JSON"

    # Get the hostname of the node
    local RESULT=$(echo "$NODE_INFO_JSON" | yq ".\"$KEY_ROLES\"" )

    # Need to save the result in the final output argument.  Note the lack
    # of single quotes around the result so that the caller doesn't get
    # "ringname" (with the double quotes) as the returned value.
    eval "$OUTPUT_VAR_NAME=$RESULT"
} # end get_node_roles_by_indices



##############################################################################
#  Get the hostname of a node from the given input JSON (which supposedly
#  contains the information about this node).  Throws an error if the input
#  JSON does not contain the hostname key.
#
#  Arguments:
#  * 1st arg -- the input JSON containing all information about the node
#  * 2nd arg -- the name of the variable in which the result will be stored
#
#  Returns:
#      The hostname extracted from the given JSON.
##############################################################################
function get_node_hostname_from_json
{
    local INPUT_JSON="$1"
    local OUTPUT_VAR_NAME="$2"

    # Get the hostname out of the given input
    # Note: Do NOt use 'RESULT' as the 3rd parameter for this function;
    #       it doesn't work for some reason
    get_param_value_from_json "$INPUT_JSON" "$KEY_HOSTNAME" "HOSTNAME"

    # Need to save the result in the final output argument.  Note the lack
    # of single quotes around the result so that the caller doesn't get
    # "ringname" (with the double quotes) as the returned value.
    eval "$OUTPUT_VAR_NAME=$HOSTNAME"
} # end get_node_hostname_from_json


##############################################################################
#  Get the IP address of a node from the given input JSON (which supposedly
#  contains the information about this node).  Throws an error if the input
#  JSON does not contain the IP address key.
#
#  Arguments:
#  * 1st arg -- the input JSON containing all information about the node
#  * 2nd arg -- the name of the variable in which the result will be stored
#
#  Returns:
#      The IP address extracted from the given JSON.
##############################################################################
function get_node_ip_from_json
{
    local INPUT_JSON="$1"
    local OUTPUT_VAR_NAME="$2"

    # Get the hostname out of the given input
    # Note: Do NOt use 'RESULT' as the 3rd parameter for this function;
    #       it doesn't work for some reason
    get_param_value_from_json "$INPUT_JSON" "$KEY_IP_ADDR" "IP_ADDR"

    # Need to save the result in the final output argument.  Note the lack
    # of single quotes around the result so that the caller doesn't get
    # "ringname" (with the double quotes) as the returned value.
    eval "$OUTPUT_VAR_NAME=$IP_ADDR"
} # end get_node_ip_from_json


##############################################################################
#  Get the roles of a node from the given input JSON (which supposedly
#  contains the information about this node).  Throws an error if the input
#  JSON does not contain the roles key.
#
#  Arguments:
#  * 1st arg -- the input JSON containing all information about the node
#  * 2nd arg -- the name of the variable in which the result will be stored
#
#  Returns:
#      The roles extracted from the given JSON.
##############################################################################
function get_node_roles_from_json
{
    local INPUT_JSON="$1"
    local OUTPUT_VAR_NAME="$2"

    # Get the roles out of the given input
    # Note: Do NOt use 'RESULT' as the 3rd parameter for this function;
    #       it doesn't work for some reason
    get_param_value_from_json "$INPUT_JSON" "$KEY_ROLES" "ROLES"

    # Need to save the result in the final output argument.  Note the lack
    # of single quotes around the result so that the caller doesn't get
    # "ringname" (with the double quotes) as the returned value.
    eval "$OUTPUT_VAR_NAME=$ROLES"
} # end get_node_roles_from_json

# Tests ------------------------

# Declared for testing purposes (need to have it set by the calling
# script)
# CONFIG_FILE="$ROOT_DIR/config/config.template.yml"  # debug~~~

# import our common functions
# COMMON_SCRIPTS_DIR="$SCRIPT_DIR"
# source "$COMMON_SCRIPTS_DIR/common.sh"

# validate_top_level_keys "I1"
# echo I1 "$I1"

# validate_docker_keys "I2"
# echo I2 "$I2"

# validate_kagent_keys "I3"
# echo I3 "$I3"

# validate_provision_keys "I4"
# echo I4 "$I4"


# get_param_value_from_section "docker" "project-name" "I5"
# echo I5 "'$I5'"

# get_param_value_from_section "provision" "on-prem" "I6"
# echo I6 "$I6"


# get_section_params "provision" "I7"
# echo I7 "$I7"


# get_docker_params "I8"
# echo I8 "$I8"

# get_kagent_params "I8"
# echo I8 "$I8"

# get_provision_params "I8"
# echo I8 "$I8"

# get_rings_params "I8"
# echo I8 "$I8"

# get_docker_project_name "OUT"
# echo OUT "'$OUT'"

# get_docker_kagent_dockerfile "OUT"
# echo OUT "$OUT"

# get_docker_kinetica_dockerfile "OUT"
# echo OUT "$OUT"

# get_docker_mount_base_dir "OUT"
# echo OUT "$OUT"

# get_docker_kagent_image_name "OUT"
# echo OUT "$OUT"

# get_docker_kinetica_image_name "OUT"
# echo OUT "$OUT"

# get_kagent_ip_address "OUT"
# echo OUT "$OUT"

# get_provision_kinetica_version "OUT"
# echo OUT "$OUT"

# get_provision_admin_password "OUT"
# echo OUT "$OUT"

# get_cloud_params_local_ssh_key_dir "OUT"
# echo OUT "$OUT"

# get_cloud_params_kagent_ssh_key_dir "OUT"
# echo OUT "$OUT"

# get_cloud_params_sudo_password "OUT"
# echo OUT "$OUT"

# is_provision_for_on_prem "OUT"
# echo OUT "$OUT"

# get_provision_on_prem_ssh_user "OUT"
# echo OUT "$OUT"

# get_provision_on_prem_ssh_password "OUT"
# echo OUT "$OUT"

# get_num_rings "I9"
# echo I9 "$I9"

# get_ring_info_by_index "1" "I10"
# echo I10 "$I10"

# get_ring_index_from_name "r1" "OUT"
# echo OUT "$OUT"

# # Should return null
# get_ring_index_from_name "r3" "OUT"
# echo OUT "$OUT"

# get_ring_info_by_name "r1" "OUT"
# echo OUT "$OUT"

# Will throw an error and exit the program; so keep this commented out unless
# testing
# get_ring_info_by_name "r3" "OUT"
# echo OUT "$OUT"

# get_num_clusters_by_ring_index "0" "OUT"
# echo OUT "$OUT"

# get_num_clusters_by_ring_name "r2" "OUT"
# echo OUT "$OUT"

# get_all_clusters_by_ring_index "0" "OUT"
# echo OUT "$OUT"

# # Will throw an error and exit the program; so keep this commented out unless
# # testing
# get_all_clusters_by_ring_index "2" "OUT"
# echo OUT "$OUT"

# get_all_clusters_by_ring_name "r1" "OUT"
# echo OUT "$OUT"

# # Will throw an error and exit the program; so keep this commented out unless
# # testing
# get_all_clusters_by_ring_name "r11" "OUT"
# echo OUT "$OUT"



# get_cluster_info_by_indices "0" "0" "OUT"
# echo OUT "$OUT"

# # Will throw an error and exit the program; so keep this commented out unless
# # testing
# get_cluster_info_by_indices "0" "1" "OUT"
# echo OUT "$OUT"


# get_cluster_info_by_names "r2" "r2c2" "OUT"
# echo OUT "$OUT"

# # # Will throw an error and exit the program; so keep this commented out unless
# # # testing
# get_cluster_info_by_names "r2" "r1c2" "OUT"
# echo OUT "$OUT"

# is_cluster_np1_enabled_by_indices 0 0 "OUT"
# echo OUT "$OUT"

# get_num_nodes_by_names "r2" "r2c1" "OUT"
# echo OUT "$OUT"

# get_all_nodes_by_indices 0 0 "OUT"
# echo OUT "$OUT"

# get_all_nodes_by_names "r2" "r2c1" "OUT"
# echo OUT "$OUT"

# get_node_info_by_indices 0 0 1 "OUT"
# echo OUT "$OUT"

# # Will throw an error and exit the program; so keep this commented out unless
# # testing
# get_node_info_by_indices 0 0 3 "OUT"
# echo OUT "$OUT"

# get_node_info_by_names "r1" "r1c1" "r1c1n1" "OUT"
# echo OUT "$OUT"

# # Will throw an error and exit the program; so keep this commented out unless
# # testing
# get_node_info_by_names "r1" "r1c1" "r1c1n3" "OUT"
# echo OUT "$OUT"

# get_node_hostname_by_indices 0 0 1 "OUT"
# echo OUT "$OUT"

# # Will throw an error and exit the program; so keep this commented out unless
# # testing
# get_node_hostname_by_indices 0 0 3 "OUT"
# echo OUT "$OUT"

# get_node_ip_by_indices 0 0 1 "OUT"
# echo OUT "$OUT"

# # Will throw an error and exit the program; so keep this commented out unless
# # testing
# get_node_ip_by_indices 0 0 3 "OUT"
# echo OUT "$OUT"

# get_node_roles_by_indices 0 0 1 "OUT"
# echo OUT "$OUT"

# # Will throw an error and exit the program; so keep this commented out unless
# # testing
# get_node_roles_by_indices 0 0 3 "OUT"
# echo OUT "$OUT"


###########################################
# Example of looping over all the rings
###########################################
function run_example_ring_processing
{
    # Need to get the total number of rings first
    get_num_rings "NUM_RINGS"
    echo "Configuration file has $NUM_RINGS ring(s)"

    # Loop over the rings by index; note that the spaces and
    # lack of $ in the variables are critical to the syntax!
    for ((RING_INDEX=0; RING_INDEX < NUM_RINGS ; RING_INDEX++)); do
        echo "Working on ring with index $RING_INDEX"

        # Get the ring name using the index.
        # Note: We need to supply the ring index in the first parameter (so we
        #       need the $), and the second parameter is the name of the output
        #       variable (so it doesn't get the $).  This is true of most getter
        #       functions in this script (that the last parameter is the name of
        #       the output variable).
        get_ring_name_by_index "$RING_INDEX" "RING_NAME"
        echo "Working on ring named '$RING_NAME'"

        # Is this ring HA enabled?
        is_ring_ha_enabled_by_index "$RING_INDEX" "IS_HA_ENABLED"
        if [ $IS_HA_ENABLED -eq 1 ]; then
            echo "The ring is enabled for HA"
        else
            echo "The ring is not enabled for HA"
        fi

        # Need to get the total number of clusters before looping over them
        get_num_clusters_by_ring_index "$RING_INDEX" "NUM_CLUSTERS"
        echo "Ring has $NUM_CLUSTERS cluster(s)"

        # Loop over the clusters by index; note that the spaces and
        # lack of $ in the variables are critical to the syntax!
        for ((CLUSTER_INDEX=0; CLUSTER_INDEX < NUM_CLUSTERS ; CLUSTER_INDEX++)); do
            echo "Working on cluster with index $CLUSTER_INDEX"

            # Get the ring name using the index
            # Note: The first TWO values passed are input arguments to identify
            #       the cluster we want to work with.  The last argument is the
            #       _name_ of the output variable.
            get_cluster_name_by_indices "$RING_INDEX" "$CLUSTER_INDEX" "CLUSTER_NAME"
            echo "Working on cluster named '$CLUSTER_NAME'"


            # Get whether this cluster is supposed to be enabled for N+1 resiliency
            is_cluster_np1_enabled_by_indices "$RING_INDEX" "$CLUSTER_INDEX" "IS_NP1_ENABLED"
            if [ $IS_NP1_ENABLED -eq 1 ]; then
                echo "The cluster is enabled for N+1"
            else
                echo "The cluster is not enabled for N+1"
            fi

            # Do pre-node-installation stuff here

            # Need to get the total number of nodes before looping over them
            get_num_nodes_by_indices "$RING_INDEX" "$CLUSTER_INDEX" "NUM_NODES"
            echo "Cluster has $NUM_NODES node(s)"

            # Loop over the clusters by index; note that the spaces and
            # lack of $ in the variables are critical to the syntax!
            for ((NODE_INDEX=0; NODE_INDEX < NUM_NODES ; NODE_INDEX++)); do
                echo "Working on node with index $NODE_INDEX"

                # Get all information pertaining to this node
                get_node_info_by_indices "$RING_INDEX" "$CLUSTER_INDEX" "$NODE_INDEX" "NODE_INFO_JSON"
                echo NODE_INFO_JSON "$NODE_INFO_JSON"

                # Get the node's hostname
                get_node_hostname_from_json "$NODE_INFO_JSON" "NODE_HOSTNAME"
                echo "Hostname of the node: $NODE_HOSTNAME"

                # Get the node's IP address
                get_node_ip_from_json "$NODE_INFO_JSON" "NODE_IP"
                echo "IP address of the node: $NODE_IP"

                # Get the node's roles
                get_node_roles_from_json "$NODE_INFO_JSON" "NODE_ROLES"
                echo "Roles of the node: $NODE_ROLES"

                # Do individual node stuff here using the hostname, IP, and roles
            done # node loop

            # Do post-node installation stuff here
        done # cluster loop

        # Do any HA related stuff here

    done # ring loop
} # end run_example_ring_processing



# run_example_ring_processing

# validate_config_file "OUT"
# echo "Is the config file valid?: " "$OUT"
