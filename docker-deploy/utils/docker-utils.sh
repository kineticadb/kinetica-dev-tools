#!/usr/bin/env bash

##############################################################################
#  This script generates a docker-compose configuration Yaml file based
#  on the config file for this project.
##############################################################################


SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
ROOT_DIR="$SCRIPT_DIR/.."


# Note: We're assuming that the following variables have already beed declared
#       elsewhere:
#       1) Project configuration file ($CONFIG_FILE)
#       2) Log filename ($LOG)
#
#       If not, then some or all of the functionality will not execute properly.
#       The errors may contain the variable names in them.


# ##################################################################
#     HELPER FUNCTIONS FOR GENERATING DOCKER COMPOSE CONFIG FILE
# ##################################################################

##############################################################################
#  Generates the beginning/top of the docker-compose configuration file.
#
#  Arguments:
#  * 1st arg -- the name of the variable in which the result will be stored
#
#  Returns:
#      A multi-line string containing the beginning of the config file; please
#      use the output variable within double quotes to ensure the newlines get
#      printed properly.
##############################################################################
function generate_docker_compose_beginning
{
    local OUTPUT_VAR_NAME="$1"

    # Need to escape the quotes
    local CONFIG_TEXT="---
version: \"3.7\"
"

    # Need to save the result in the final output argument; need the single
    # quotes around the multi-line string so that it is not evaluated as a
    # bash command
    eval "$OUTPUT_VAR_NAME='$CONFIG_TEXT'"
} # end generate_docker_compose_beginning


##############################################################################
#  Generates the networks section of the docker compose file.  This function
#  does not take any argument.
#
#  Arguments:
#  * 1st arg -- the name of the variable in which the result will be stored
#
#  Returns:
#      A multi-line string containing the 'networks' section; please use
#      the output variable within double quotes to ensure the newlines get
#      printed properly.
##############################################################################
function generate_docker_compose_networks
{
    local OUTPUT_VAR_NAME="$1"

    # Get some relevant parameters from the config file
    get_docker_network_name "DOCKER_NETWORK_NAME"
    get_docker_subnet "SUBNET"

    # This should preserve the spacing
    local NETWORKS_SECTION="networks:
    $DOCKER_NETWORK_NAME:
        ipam:
            config:
                - subnet: ${SUBNET}
"

    # Need to save the result in the final output argument; need the single
    # quotes around the multi-line string so that it is not evaluated as a
    # bash command
    eval "$OUTPUT_VAR_NAME='$NETWORKS_SECTION'"
} # end generate_docker_compose_networks



##############################################################################
#  Generates the kagent service section (including the 'services' lable).
#  Uses parameters found in the configuration file for this project, e.g.
#  dockerfile name, IP address for the kagent container.
#
#  Arguments:
#  * 1st arg -- the name of the variable in which the result will be stored
#
#  Returns:
#      A multi-line string containing the 'kagent' service; please use
#      the output variable within double quotes to ensure the newlines get
#      printed properly.
##############################################################################
function generate_docker_compose_service_kagent
{
    local OUTPUT_VAR_NAME="$1"

    # Get the relevant parameters from the project config file
    get_docker_network_name "DOCKER_NETWORK_NAME"
    get_docker_kagent_dockerfile "KAGENT_DOCKERFILE"
    get_docker_kagent_image_name "KAGENT_IMAGE_NAME"
    get_kagent_ip_address "KAGENT_IP_ADDRESS"

    # Create the container name from the image name and add ':latest' to
    # the image name
    # TODO: Maybe the container and image names should be separately listed
    #       in the config file?
    KAGENT_CONTAINER_NAME="$KAGENT_IMAGE_NAME"
    KAGENT_IMAGE_NAME="$KAGENT_IMAGE_NAME:latest"

    # We need to expose ports for Mac OS only
    is_mac_os "IS_MAC_OS"
    if [ $IS_MAC_OS -eq 1 ]; then
        PORTS_DIRECTIVE="
        ports:
            - 8081:8081"
    else
        PORTS_DIRECTIVE=""
    fi


    # Put the KAgent service together.  Note that PORTS_DIRECTIVE is put on the
    # "image" line without any spaces.  If we put this variable on a
    # line of its own, then we would have extra newline when there isn't
    # any of ports directive.
    local KAGENT_SERVICE="services:
    kagent:
        build:
            context: ../
            dockerfile: $KAGENT_DOCKERFILE
        image: $KAGENT_IMAGE_NAME$PORTS_DIRECTIVE
        networks:
            $DOCKER_NETWORK_NAME:
                ipv4_address: $KAGENT_IP_ADDRESS
        privileged: true
        container_name: $KAGENT_CONTAINER_NAME
"

    # Need to save the result in the final output argument; need the single
    # quotes around the multi-line string so that it is not evaluated as a
    # bash command
    eval "$OUTPUT_VAR_NAME='$KAGENT_SERVICE'"
} # end generate_docker_compose_service_kagent



##############################################################################
#  Generates a kinetica service section.   Uses parameters found in the
#  configuration file for this project, e.g. dockerfile name, IP address for
#  the kinetica container.
#
#  Arguments:
#  * 1st arg -- the network name for the docker containers
#  * 2nd arg -- the dockerfile for kinetica
#  * 3rd arg -- the name of the Kinetica docker image
#  * 4th arg -- the hostname of the Kinetica container
#  * 5th arg -- the IP address for the container
#  * 6th arg -- the path for mounting the persist volume
#  * 7th arg -- name of the container that this container should depend on.
#               If this is the first container to be created, must pass an
#               empty string.
#  * 8th arg -- the name of the variable in which the result will be stored
#
#  Returns:
#      A multi-line string containing the service for one kinetica container;
#      please use the output variable within double quotes to ensure the
#      newlines get printed properly.
##############################################################################
function generate_docker_compose_service_kinetica
{
    local DOCKER_NETWORK_NAME="$1"
    local KINETICA_DOCKERFILE="$2"
    local KINETICA_IMAGE_NAME="$3"
    local KINETICA_HOSTNAME="$4"
    local KINETICA_IP_ADDRESS="$5"
    local KINETICA_VOLUME_PATH="$6"
    local DEPENDS_ON_CONTAINER="$7"
    local OUTPUT_VAR_NAME="$8"

    # Use the hostname as the service and container names
    KINETICA_CONTAINER_NAME="$KINETICA_HOSTNAME"
    KINETICA_SERVICE_NAME="$KINETICA_HOSTNAME"

    # The very first Kinetica container will need to build the image from
    # the dockerfile and save it.  Later containers will depend upon it.
    if [ -z "$DEPENDS_ON_CONTAINER" ]; then
        # We're handling the "first" kinetica container since no dependency
        # was provided; so we need a build directive
        BUILD_DIRECTIVE="
        build:
            context: ../
            dockerfile: $KINETICA_DOCKERFILE"
        # We don't have any dependency
        DEPENDENCY_DIRECTIVE=""
    else
        # This is NOT the first container, so we won't need to build
        # the image
        BUILD_DIRECTIVE=""
        # However, we will have a dependency on the first container
        DEPENDENCY_DIRECTIVE="
        depends_on:
            - $DEPENDS_ON_CONTAINER"
    fi

    # The very first Kinetica container will need to build the image from
    # the dockerfile and save it.  Later containers will depend upon it.
    if [ -z "$KINETICA_VOLUME_PATH" ]; then
        # No mount directory provide, so we won't need the mount directive
        MOUNT_DIRECTIVE=""
    else
        # Mount the given path for the persist directory
        MOUNT_DIRECTIVE="
        volumes:
            - $KINETICA_VOLUME_PATH:/opt/gpudb/persist"
    fi

    # We need to expose ports for Mac OS only
    is_mac_os "IS_MAC_OS"
    if [ $IS_MAC_OS -eq 1 ]; then
        PORTS_DIRECTIVE="
        # Need to open up some ports
        ports:
            - 8080
            - 8088
            - 9049
            - 9050
            - 9191"
    else
        PORTS_DIRECTIVE=""
    fi

    # Put all the optional directives in one spot
    OPTIONAL_DIRECTIVES="$BUILD_DIRECTIVE$DEPENDENCY_DIRECTIVE"
    OPTIONAL_DIRECTIVES+="$MOUNT_DIRECTIVE$PORTS_DIRECTIVE"

    # Put everything together.  Note that OPTIONAL_DIRECTIVES is put on the
    # "image" line without any spaces.  If we put this variable on a
    # line of its own, then we would have extra newline when there isn't
    # any of the optional directives.
    local KINETICA_SERVICE="
    $KINETICA_SERVICE_NAME:
        privileged: true
        image: $KINETICA_IMAGE_NAME$OPTIONAL_DIRECTIVES
        networks:
            $DOCKER_NETWORK_NAME:
                ipv4_address: $KINETICA_IP_ADDRESS
        container_name: $KINETICA_CONTAINER_NAME
"

    # Need to save the result in the final output argument; need the single
    # quotes around the multi-line string so that it is not evaluated as a
    # bash command
    eval "$OUTPUT_VAR_NAME=\"$KINETICA_SERVICE\""
} # end generate_docker_compose_service_kinetica






##############################################################################
#  Loops over the ring configuration and generates all the sections for
#  the docker-compose config file for the containers meant for running
#  Kinetica on them.
#
#  Arguments:
#  * 1st arg -- the name of the variable in which the result will be stored
#
#  Returns:
#      A multi-line string containing the services for all the kinetica
#      containers; please use the output variable within double quotes to
#      ensure the newlines get printed properly.
##############################################################################
function generate_kinetica_services
{
    local OUTPUT_VAR_NAME="$1"

    KINETICA_SERVICES_SECTION=""

    # Get some information from the config that we'll need per container
    get_docker_network_name "DOCKER_NETWORK_NAME"
    get_docker_kinetica_dockerfile "KINETICA_DOCKERFILE"
    get_docker_kinetica_image_name "KINETICA_IMAGE_NAME"
    get_docker_mount_base_dir "MOUNT_BASE_DIR"

    # Ensure that the base mount directory exists (create if it does not)
    MOUNT_BASE_DIR_ARRAY=($MOUNT_BASE_DIR)
    dir_setup ${MOUNT_BASE_DIR_ARRAY[@]}


    # Need to get the total number of rings before looping over them
    get_num_rings "NUM_RINGS"

    # Loop over the rings by index; note that the spaces and
    # lack of $ in the variables are critical to the syntax!
    for ((RING_INDEX=0; RING_INDEX < NUM_RINGS ; RING_INDEX++)); do

        # Need to get the total number of clusters before looping over them
        get_num_clusters_by_ring_index "$RING_INDEX" "NUM_CLUSTERS"

        # Loop over the clusters by index; note that the spaces and
        # lack of $ in the variables are critical to the syntax!
        for ((CLUSTER_INDEX=0; CLUSTER_INDEX < NUM_CLUSTERS ; CLUSTER_INDEX++)); do

            # Get the ring name using the index
            # Note: The first TWO values passed are input arguments to identify
            #       the cluster we want to work with.  The last argument is the
            #       _name_ of the output variable.
            get_cluster_name_by_indices "$RING_INDEX" "$CLUSTER_INDEX" "CLUSTER_NAME"

            # Get whether this cluster is supposed to be enabled for N+1 resiliency
            is_cluster_np1_enabled_by_indices "$RING_INDEX" "$CLUSTER_INDEX" "IS_NP1_ENABLED"

            # If the cluster is supposed to be N+1 enabled, then all nodes will
            # get the same directory mounted for the persist directory; if no N+1,
            # then each node will get its own mount directory.
            if [ $IS_NP1_ENABLED -eq 1 ]; then
                # Create a single mount directory using the cluster name (inside
                # of the base directory for the mount directories)
                MOUNT_DIR="$MOUNT_BASE_DIR/$CLUSTER_NAME"

                # Now ensure that the directory exists (create if it does not)
                MOUNT_DIR_ARRAY=($MOUNT_DIR)
                dir_setup ${MOUNT_DIR_ARRAY[@]}
            else
                # An empty string will signify that no volume needs to be mounted
                MOUNT_DIR=""
            fi

            # Need to get the total number of nodes before looping over them
            get_num_nodes_by_indices "$RING_INDEX" "$CLUSTER_INDEX" "NUM_NODES"

            # Loop over the clusters by index; note that the spaces and
            # lack of $ in the variables are critical to the syntax!
            for ((NODE_INDEX=0; NODE_INDEX < NUM_NODES ; NODE_INDEX++)); do

                # Get all information pertaining to this node
                get_node_info_by_indices "$RING_INDEX" "$CLUSTER_INDEX" "$NODE_INDEX" "NODE_INFO_JSON"

                # Get the node's hostname
                get_node_hostname_from_json "$NODE_INFO_JSON" "KINETICA_HOSTNAME"

                # For the very first container, we need to build the image and will
                # not have any dependency on other containers.  For all the rest of
                # the Kinetica containers, we will have this first container as a
                # dependency
                if [[ $RING_INDEX -eq 0 && $CLUSTER_INDEX -eq 0 && $NODE_INDEX -eq 0 ]]; then
                    # All other containers will depend on this one
                    FIRST_KINETICA_CONTAINER_NAME=$KINETICA_HOSTNAME
                    # But this container won't have any dependency directive
                    CONTAINER_DEPENDENCY=""
                else
                    # this container will a dependency directive (dependent on
                    # the first Kinetica container)
                    CONTAINER_DEPENDENCY=$FIRST_KINETICA_CONTAINER_NAME
                fi

                # Get the node's IP address
                get_node_ip_from_json "$NODE_INFO_JSON" "KINETICA_IP_ADDRESS"

                # Generate the section for this container
                generate_docker_compose_service_kinetica "$DOCKER_NETWORK_NAME" \
                                                         "$KINETICA_DOCKERFILE" \
                                                         "$KINETICA_IMAGE_NAME" \
                                                         "$KINETICA_HOSTNAME" \
                                                         "$KINETICA_IP_ADDRESS" \
                                                         "$MOUNT_DIR" \
                                                         "$CONTAINER_DEPENDENCY" \
                                                         "OUTPUT"

                # Aggregate the output to the overall section text
                KINETICA_SERVICES_SECTION+="$OUTPUT"
            done # node loop
        done # cluster loop
    done # ring loop

    # Return the result via the output variable
    eval "$OUTPUT_VAR_NAME=\"$KINETICA_SERVICES_SECTION\""
} # end generate_kinetica_services





##############################################################################
#  Generates the docker-compose file.  Writes the content to the given
#  filename, prompting the user for overwriting any existing file.  If user
#  says not to overwrite, simply returns without generating the content.
#
#  Arguments:
#  * 1st arg -- the name of docker-compose config file.
#
#  Returns:
#      Nothing
##############################################################################
function generate_docker_compose_config_file
{
    local DOCKER_COMPOSE_CONFIG_FILE="$1"

    # Check if the given file already exists; if not to be overwritten, return
    if [ -f "$DOCKER_COMPOSE_CONFIG_FILE" ]; then
        log "docker-compose configuration file $DOCKER_COMPOSE_CONFIG_FILE already exists; overwrite (y/n)? "
        read ANSWER
        if [ $ANSWER == "y" ] || [ $ANSWER == "Y" ]; then
            log "  -- overwriting file with content generated from the project configuration file"
            run_cmd "rm -rf $DOCKER_COMPOSE_CONFIG_FILE"
        else
            log "  -- NOT overwriting file"
            return
        fi
    fi
    log

    # Generate each section
    generate_docker_compose_beginning "TOP_SECTION"
    generate_docker_compose_networks "NETWORK_SECTION"
    generate_docker_compose_service_kagent "KAGENT_SECTION"
    generate_kinetica_services "KINETICA_SECTION"

    #  Concatenate all the section to create the entire file content
    FILE_CONTENT="$TOP_SECTION$NETWORK_SECTION$KAGENT_SECTION$KINETICA_SECTION"

    # Intentionally not using run_cmd here since the whole content of the
    # file would be logged then
    echo "$FILE_CONTENT" > "$DOCKER_COMPOSE_CONFIG_FILE"
} # end generate_docker_compose_config_file





##############################################################################
#  Generates the script that sets up SSHD on the docker containers.  Writes
#  the content to the given filename, prompting the user for overwriting any
#  existing file.  If user says not to overwrite, simply returns without
#  generating the content.
#
#  Additionally, adds the execution permission to the created file (for the
#  user).
#
#  Arguments:
#  * 1st arg -- the filename for the script.
#
#  Returns:
#      Nothing
##############################################################################
function generate_docker_sshd_setup_file
{
    local DOCKER_SSHD_SETUP_FILE="$1"

    pretty_header "Docker SSHD Setup Script Generation" 4

    # Check if the given file already exists; if not to be overwritten, return
    if [ -f "$DOCKER_SSHD_SETUP_FILE" ]; then
        log "docker SSHD setup file $DOCKER_SSHD_SETUP_FILE already exists; overwrite (y/n)? "
        read ANSWER
        if [ $ANSWER == "y" ] || [ $ANSWER == "Y" ]; then
            log "  -- overwriting file with content generated from the project configuration file"
            run_cmd "rm -rf $DOCKER_SSHD_SETUP_FILE"
        else
            log "  -- NOT overwriting file"
            return
        fi
    fi

    # Get the user and password from the config file
    get_provision_on_prem_ssh_user "SSH_USERNAME"
    get_provision_on_prem_ssh_password "SSH_PASSWORD"

    # This should preserve the spacing
    local SCRIPT_CONTENT="#!/usr/bin/env bash

# Run sshd as a daemon in the background in the docker container
nohup /usr/sbin/sshd -D &

# Set the password as '$SSH_PASSWORD' for the user '$SSH_USERNAME'
echo -e \"$SSH_PASSWORD\n$SSH_PASSWORD\" | passwd $SSH_USERNAME

"

    # Intentionally not using run_cmd here since the whole content of the
    # file would be logged then
    echo "$SCRIPT_CONTENT" > "$DOCKER_SSHD_SETUP_FILE"

    # Add the execution permission for the script
    run_cmd "chmod +x $DOCKER_SSHD_SETUP_FILE"
    log

} # end generate_docker_sshd_setup_file




# Tests

# # Import the common functions
# source "$COMMON_SCRIPTS_DIR/common.sh"
# # Import the config file parser
# source "$COMMON_SCRIPTS_DIR/config-utils.sh"

# COMPOSE_CONFIG_FILE="$ROOT_DIR/docker-compose-config.yml"
# generate_docker_compose_config_file "$COMPOSE_CONFIG_FILE"

# SSHD_SETUP_FILE="$ROOT_DIR/docker-sshd-setup.sh"
# generate_docker_sshd_setup_file "$SSHD_SETUP_FILE"
