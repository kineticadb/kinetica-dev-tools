#!/usr/bin/env bash

##############################################################################
#  This script provisions and/or installs Kinetica
##############################################################################


SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"


function ring_creation(){

    ############################################################################
    #
    # This function uses the given arguments to see if a ring exists, and if it
    # doesn't, create it.
    #
    # The available arguments are as follows:
    #
    # * RING_NAME : Name of the ring to create
    #
    ############################################################################

    local RING_NAME="$1"

    pretty_header "R I N G  S E T U P: $RING_NAME" 4

    # But first see if the rings exist...
    # FIND_RING=$(/opt/gpudb/kagent/bin/kagent ring list | grep "${RING_NAME}")
    FIND_RING=$(${KAGENT_CONTAINER_BASH} "${KAGENT_EXE} ring list | grep ${RING_NAME}")

    if [ -z "${FIND_RING}" ]; then
        # FIND_RING = Empty
        log "- ${RING_NAME} does not exist!"
        # /opt/gpudb/kagent/bin/kagent ring add ${RING_NAME}
        run_cmd "${KAGENT_CONTAINER_BASH} '${KAGENT_EXE} ring add ${RING_NAME}'"
    else
        # Remove everything then re-add just in case
        log "- ${RING_NAME} already exists!"
        # /opt/gpudb/kagent/bin/kagent ring add ${RING_NAME}
        # /opt/gpudb/kagent/bin/kagent ring remove ${RING_NAME}
        run_cmd "${KAGENT_CONTAINER_BASH} '${KAGENT_EXE} ring remove ${RING_NAME}'"
        log
        run_cmd "${KAGENT_CONTAINER_BASH} '${KAGENT_EXE} ring add ${RING_NAME}'"
    fi
    log

}

function cluster_init(){

    ############################################################################
    #
    # This function uses the given arguments to initialize a cluster using the
    # KAgent CLI.
    #
    # The available arguments are as follows:
    #
    # * CLUSTER_NAME : Name of the cluster to initialize
    # * PROVIDER : Name of the infrastructure provider (onprem, aws, azure, etc.)
    # * ADMIN_PASS : Administrator password for the cluster
    # * SSH_USER : SSH user for the Kinetica containers
    # * RING_NAME : Name of the ring the cluster will belong to
    # * SSH_PASS : SSH password for the Kinetica containers
    # * LICENSE_KEY : License key for Kinetica
    #
    ############################################################################

    local CLUSTER_NAME="$1"
    local PROVIDER="$2"
    local ADMIN_PASS="$3"
    local SSH_USER="$4"
    local RING_NAME="$5"
    local SSH_PASS="$6"
    local LICENSE_KEY="$7"

    pretty_header "C L U S T E R  I N I T: $CLUSTER_NAME" 4

    run_cmd "${KAGENT_CONTAINER_BASH} '${KAGENT_EXE} --verbose cluster init \\
      $CLUSTER_NAME --infrastructure-provider=$PROVIDER \\
      --admin-pass=$ADMIN_PASS --ssh-user=$SSH_USER --ring=$RING_NAME \\
      --connect-via=public_ip_addr --ssh-password=$SSH_PASS \\
      --lic-key=$LICENSE_KEY'"
    log
    # /opt/gpudb/kagent/bin/kagent --verbose cluster init $CLUSTER_NAME \
    #     --infrastructure-provider=$PROVIDER --admin-pass=$ADMIN_PASS \
    #     --ssh-user=$SSH_USER --ring=$RING_NAME \
    #     --connect-via=public_ip_addr --ssh-password=$SSH_PASS \
    #     --lic-key=$LICENSE_KEY
    # echo ""

}

function node_init(){

    ############################################################################
    #
    # This function uses the given arguments to initialize a node using the
    # KAgent CLI.
    #
    # The available arguments are as follows:
    #
    # * NODE_HOSTNAME : Hostname of the node to initialize
    # * NODE_IP       : IP address of the node to initialize
    # * CLUSTER_NAME  : Name of the cluster to host the node
    # * ROLES         : Comma-delimited string of roles for the node
    #
    ############################################################################

    local NODE_HOSTNAME="$1"
    local NODE_IP="$2"
    local CLUSTER_NAME="$3"
    local ROLES="$4"

    pretty_header "N O D E  I N I T: $NODE_HOSTNAME" 4

    # /opt/gpudb/kagent/bin/kagent --verbose node init ${NODE_HOSTNAME} ${NODE_IP} ${CLUSTER_NAME} --roles=${ROLES} --public-ip-addr=${NODE_IP}
    # echo ""
    run_cmd "${KAGENT_CONTAINER_BASH} '${KAGENT_EXE} --verbose node init \\
      ${NODE_HOSTNAME} ${NODE_IP} ${CLUSTER_NAME} --roles=${ROLES} \\
      --public-ip-addr=${NODE_IP}'"
    log

}

function cluster_verify(){

    ############################################################################
    #
    # This function uses the given arguments to verify a cluster using the
    # KAgent CLI.
    #
    # The available arguments are as follows:
    #
    # * CLUSTER_NAME : Name of the cluster to verify
    #
    ############################################################################

    local CLUSTER_NAME="$1"

    pretty_header "C L U S T E R  V E R I F Y: $CLUSTER_NAME" 4

    # /opt/gpudb/kagent/bin/kagent --verbose cluster verify $CLUSTER_NAME
    # echo ""
    run_cmd "${KAGENT_CONTAINER_BASH} '${KAGENT_EXE} --verbose cluster verify \\
      $CLUSTER_NAME'"
    log

}

function cluster_install(){

    ############################################################################
    #
    # This function uses the given arguments to install Kinetica on a cluster 
    # using the KAgent CLI.
    #
    # The available arguments are as follows:
    #
    # * CLUSTER_NAME : Name of the cluster to install on
    #
    ############################################################################

    local CLUSTER_NAME="$1"

    pretty_header "C L U S T E R  I N S T A L L: $CLUSTER_NAME" 4

    # /opt/gpudb/kagent/bin/kagent --verbose cluster install $CLUSTER_NAME \
    #     --cuda=no --open-firewall-ports=yes --nvidia=no --auto-config=yes
    # echo ""
    run_cmd "${KAGENT_CONTAINER_BASH} '${KAGENT_EXE} --verbose cluster install \\
      $CLUSTER_NAME --cuda=no --open-firewall-ports=yes --nvidia=no \\
      --auto-config=yes'"
    log

}

function cluster_restart(){

    ############################################################################
    #
    # This function uses the given arguments to restart a cluster post-install
    # using the KAgent CLI.
    #
    # The available arguments are as follows:
    #
    # * CLUSTER_NAME : Name of the cluster to restart
    #
    ############################################################################

    local CLUSTER_NAME="$1"

    pretty_header "C L U S T E R  R E S T A R T: $CLUSTER_NAME" 4

    # /opt/gpudb/kagent/bin/kagent --verbose cluster control $CLUSTER_NAME \
    #     restart all
    # echo ""
    run_cmd "${KAGENT_CONTAINER_BASH} '${KAGENT_EXE} --verbose cluster control \\
      $CLUSTER_NAME restart all'"
    log

}

function enable_ha() {

    ############################################################################
    #
    # This function uses the given arguments to enable High Availability (HA)
    # using the KAgent CLI.
    #
    # The available arguments are as follows:
    #
    # * RING_NAME : Name of the ring to enable HA for
    #
    ############################################################################

    local RING_NAME="$1"

    pretty_header "E N A B L E  H A: $RING_NAME" 4

    # /opt/gpudb/kagent/bin/kagent --verbose ring install $RING_NAME
    # echo ""
    run_cmd "${KAGENT_CONTAINER_BASH} '${KAGENT_EXE} --verbose ring install \\
      $RING_NAME'"
    log

}

function ring_restart() {

    ############################################################################
    #
    # This function uses the given arguments to enable High Availability (HA)
    # using the KAgent CLI.
    #
    # The available arguments are as follows:
    #
    # * RING_NAME : Name of the ring to enable HA for
    #
    ############################################################################

    local RING_NAME="$1"

    pretty_header "R I N G  R E S T A R T: $RING_NAME" 4

    run_cmd "${KAGENT_CONTAINER_BASH} '${KAGENT_EXE} --verbose ring control \\
      $RING_NAME restart all'"
    log

}

function provision_kinetica
{
    ############################################################################
    #  Sets up ring and cluster then provisions Kinetica to nodes depending on
    #  provision type
    #
    # The available arguments are as follows:
    #
    # * PROVISION_TYPE : Type of Kinetica cluter to provision
    #
    #  Returns:
    #      Nothing
    ############################################################################

    ############################################################################
    # NOTE: The KAgent container name (KAGENT), executable (KAGENT_EXE), and 
    #       Docker bash command (KAGENT_CONTAINER_BASH) are exported as 
    #       environment variables in provision.sh!
    ############################################################################

    local PROVISION_TYPE="$1"

    # pretty_header "Logging Info" 4
    # DOCKER_LOG=$(${KAGENT_CONTAINER_BASH} 'echo $LOG')
    # log "Log INSIDE KAgent container '${KAGENT}' is set to '${DOCKER_LOG}'"
    # log

    # If on-prem, fix user impersonations (Docker)
    if [[ $DEPLOYMENT_TYPE == "onprem" ]]; then
      pretty_header "Etcd Configuration Fix" 4

      # The following files contain systemd rescue blocks:
      # - /opt/gpudb/kagent/resources/roles/etcd/tasks/new.yml
      # - /opt/gpudb/kagent/resources/roles/etcd/tasks/serial_restart.yml
      # The following file contains a systemd block without a rescue:
      # - /opt/gpudb/kagent/resources/roles/etcd/tasks/add_member.yml
      # All three of these files need to be owned by gpudb, be in the gpudb
      # group, and have -rw-r--r-- permissions; 'become_user: gpudb' seems to
      # present an issue...

      run_cmd "${KAGENT_CONTAINER_BASH} 'mv /opt/gpudb/kagent/resources/roles/etcd/tasks/add_member.yml /opt/gpudb/kagent/resources/roles/etcd/tasks/add_member.yml.bak'"
      run_cmd "docker cp utils/container/etcd-config/add_member.yml ${KAGENT}:/opt/gpudb/kagent/resources/roles/etcd/tasks/"
      run_cmd "docker exec ${KAGENT} bash -c 'chown gpudb:gpudb /opt/gpudb/kagent/resources/roles/etcd/tasks/add_member.yml'"
      run_cmd "${KAGENT_CONTAINER_BASH} \"find /opt/gpudb/kagent/resources/roles/etcd/tasks/new.yml -type f -exec sed -i.bak -e 's/become_user: gpudb/# become_user: gpudb/g' {} \;\""
      run_cmd "${KAGENT_CONTAINER_BASH} \"find /opt/gpudb/kagent/resources/roles/etcd/tasks/serial_restart.yml -type f -exec sed -i.bak -e 's/become_user: gpudb/# become_user: gpudb/g' {} \;\""
      log
    fi
    pretty_header "divider" # debug~~~

    # Need to get the total number of rings first
    get_num_rings "NUM_RINGS"
    log "Configuration file has $NUM_RINGS ring(s)" # debug~~~

    # Loop over the rings by index; note that the spaces and
    # lack of $ in the variables are critical to the syntax!
    for ((RING_INDEX=0; RING_INDEX < NUM_RINGS ; RING_INDEX++)); do
      log "Working on ring with index $RING_INDEX" # debug~~~
      
      # Get the ring name using the index.
      # Note: We need to supply the ring index in the first parameter (so we
      #       need the $), and the second parameter is the name of the output
      #       variable (so it doesn't get the $).  This is true of most getter
      #       functions in this script (that the last parameter is the name of
      #       the output variable).
      get_ring_name_by_index "$RING_INDEX" "RING_NAME"
      log "Working on ring named '$RING_NAME'" # debug~~~

      # Create rings for the clusters
      ring_creation $RING_NAME
      pretty_header "divider" # debug~~~

      # Need to get the total number of clusters before looping over them
      get_num_clusters_by_ring_index "$RING_INDEX" "NUM_CLUSTERS"
      log "Ring has $NUM_CLUSTERS cluster(s)" # debug~~~

      # Loop over the clusters by index; note that the spaces and
      # lack of $ in the variables are critical to the syntax!
      for ((CLUSTER_INDEX=0; CLUSTER_INDEX < NUM_CLUSTERS ; CLUSTER_INDEX++)); do
          log "Working on cluster with index $CLUSTER_INDEX" # debug~~~

          # Get the ring name using the index
          # Note: The first TWO values passed are input arguments to identify
          #       the cluster we want to work with.  The last argument is the
          #       _name_ of the output variable.
          get_cluster_name_by_indices "$RING_INDEX" "$CLUSTER_INDEX" "CLUSTER_NAME"
          log "Working on cluster named '$CLUSTER_NAME'" # debug~~~

          # Get whether this cluster is supposed to be enabled for N+1 resiliency
          is_cluster_np1_enabled_by_indices "$RING_INDEX" "$CLUSTER_INDEX" "IS_NP1_ENABLED"
          if [ $IS_NP1_ENABLED -eq 1 ]; then
              log "The cluster is enabled for N+1" # debug~~~
          else
              log "The cluster is not enabled for N+1" # debug~~~
          fi

          # Do pre-node-installation stuff here
          get_provision_admin_password "ADMIN_PASS"
          get_provision_on_prem_ssh_user "SSH_USER"
          get_provision_on_prem_ssh_password "SSH_PASS"
          get_provision_kinetica_license "LICENSE_KEY"
          PROVIDER="$DEPLOYMENT_TYPE"

          # log "Cluster essentials:" # debug~~~
          # log "- cluster name : $CLUSTER_NAME" # debug~~~
          # log "- provider     : $PROVIDER" # debug~~~
          # log "- admin pass   : $ADMIN_PASS" # debug~~~
          # log "- ssh user     : $SSH_USER" # debug~~~
          # log "- ring name    : $RING_NAME" # debug~~~
          # log "- ssh pass     : $SSH_PASS" # debug~~~
          # log "- license      : $LICENSE_KEY" # debug~~~
          cluster_init $CLUSTER_NAME $PROVIDER $ADMIN_PASS $SSH_USER $RING_NAME $SSH_PASS $LICENSE_KEY
          pretty_header "divider" # debug~~~

          # Need to get the total number of nodes before looping over them
          get_num_nodes_by_indices "$RING_INDEX" "$CLUSTER_INDEX" "NUM_NODES"
          echo "Cluster has $NUM_NODES node(s)" # debug~~~

          # Loop over the clusters by index; note that the spaces and
          # lack of $ in the variables are critical to the syntax!
          for ((NODE_INDEX=0; NODE_INDEX < NUM_NODES ; NODE_INDEX++)); do
              echo "Working on node with index $NODE_INDEX" # debug~~~

              # Get all information pertaining to this node
              get_node_info_by_indices "$RING_INDEX" "$CLUSTER_INDEX" "$NODE_INDEX" "NODE_INFO_JSON"
              log NODE_INFO_JSON "$NODE_INFO_JSON" # debug~~~

              # Get the node's hostname
              get_node_hostname_from_json "$NODE_INFO_JSON" "NODE_HOSTNAME"
              log "Hostname of the node: $NODE_HOSTNAME" # debug~~~

              # Get the node's IP address
              get_node_ip_from_json "$NODE_INFO_JSON" "NODE_IP"
              log "IP address of the node: $NODE_IP" # debug~~~

              # Get the node's roles
              get_node_roles_from_json "$NODE_INFO_JSON" "NODE_ROLES"
              log "Roles of the node: $NODE_ROLES" # debug~~~

              # Do individual node stuff here using the hostname, IP, and roles
              node_init $NODE_HOSTNAME $NODE_IP $CLUSTER_NAME $ROLES
              pretty_header "divider" # debug~~~
          done # node loop

          # Do post-node installation stuff here
          cluster_verify $CLUSTER_NAME
          pretty_header "divider" # debug~~~
          cluster_install $CLUSTER_NAME
          pretty_header "divider" # debug~~~
          cluster_restart $CLUSTER_NAME
          pretty_header "divider" # debug~~~
      done # cluster loop

      # Do any HA related stuff here
      # Is this ring HA enabled?
      is_ring_ha_enabled_by_index "$RING_INDEX" "IS_HA_ENABLED"
      if [ $IS_HA_ENABLED -eq 1 ]; then
          echo "The ring is enabled for HA" # debug~~~
          enable_ha $RING_NAME
      else
          echo "The ring is not enabled for HA" # debug~~~
      fi

      # Ensure everything's started post HA install
      ring_restart $RING_NAME
    done # ring loop

} # end provision_kinetica
