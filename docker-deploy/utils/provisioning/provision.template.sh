#!/usr/bin/env bash


THIS_SCRIPT=$(basename ${BASH_SOURCE[0]})
THIS_SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
export CONFIG_FILE=config.yml # debug~~~


# Source script(s)
source ${THIS_SCRIPT_DIR}/utils/common.sh
source ${THIS_SCRIPT_DIR}/utils/config-utils.sh
source ${THIS_SCRIPT_DIR}/utils/provision-utils.sh

pretty_header "~~~ P R O V I S I O N  S T A R T ~~~" 3

# Fix for etcd
pretty_header "E T C D  C O N F  F I X" 4
echo "Removing ansible 'gpudb' user impersonations... (Docker compatibility issue)"
# grep -rnw '/opt/gpudb/kagent/resources/' -e 'become_user: gpudb'
find /opt/gpudb/kagent/resources/etcd_gpudb_conf.yml -type f -exec sed -i.bak -e 's/become: yes/# become: yes/g; s/become_user: gpudb/# become_user: gpudb/g' {} \;
find /opt/gpudb/kagent/resources/roles/etcd/ -type f -exec sed -i.bak -e 's/become: yes/# become: yes/g; s/become_user: gpudb/# become_user: gpudb/g' {} \;
find /opt/gpudb/kagent/resources/roles/etcd/tasks/add_member.yml -type f -exec sed -i.bak -e 's|systemd:|shell: /opt/gpudb/etcd/gpudb-etcd.sh stop|g;' {} \;
find /opt/gpudb/kagent/resources/roles/etcd/tasks/add_member.yml -type f -exec sed -i.bak -e 's/name: kinetica-etcd/# name: kinetica-etcd/g; s/state: stopped/# state: stopped/g' {} \;
pretty_header "divider" # debug~~~

# Need to get the total number of rings first
get_num_rings "NUM_RINGS"
echo "Configuration file has $NUM_RINGS ring(s)" # debug~~~

# Loop over the rings by index; note that the spaces and
# lack of $ in the variables are critical to the syntax!
for ((RING_INDEX=0; RING_INDEX < NUM_RINGS ; RING_INDEX++)); do
  echo "Working on ring with index $RING_INDEX" # debug~~~
  
  # Get the ring name using the index.
  # Note: We need to supply the ring index in the first parameter (so we
  #       need the $), and the second parameter is the name of the output
  #       variable (so it doesn't get the $).  This is true of most getter
  #       functions in this script (that the last parameter is the name of
  #       the output variable).
  get_ring_name_by_index "$RING_INDEX" "RING_NAME"
  echo "Working on ring named '$RING_NAME'" # debug~~~

  # Create rings for the clusters
  ring_creation ${RING_NAME}
  pretty_header "divider" # debug~~~

  # Need to get the total number of clusters before looping over them
  get_num_clusters_by_ring_index "$RING_INDEX" "NUM_CLUSTERS"
  echo "Ring has $NUM_CLUSTERS cluster(s)" # debug~~~

  # Loop over the clusters by index; note that the spaces and
  # lack of $ in the variables are critical to the syntax!
  for ((CLUSTER_INDEX=0; CLUSTER_INDEX < NUM_CLUSTERS ; CLUSTER_INDEX++)); do
      echo "Working on cluster with index $CLUSTER_INDEX" # debug~~~

      # Get the ring name using the index
      # Note: The first TWO values passed are input arguments to identify
      #       the cluster we want to work with.  The last argument is the
      #       _name_ of the output variable.
      get_cluster_name_by_indices "$RING_INDEX" "$CLUSTER_INDEX" "CLUSTER_NAME"
      echo "Working on cluster named '$CLUSTER_NAME'" # debug~~~

      # Get whether this cluster is supposed to be enabled for N+1 resiliency
      is_cluster_np1_enabled_by_indices "$RING_INDEX" "$CLUSTER_INDEX" "IS_NP1_ENABLED"
      if [ $IS_NP1_ENABLED -eq 1 ]; then
          echo "The cluster is enabled for N+1" # debug~~~
      else
          echo "The cluster is not enabled for N+1" # debug~~~
      fi

      # Do pre-node-installation stuff here
      PROVIDER="onprem" # debug~~~
      get_provision_admin_password "ADMIN_PASS"
      get_provision_on_prem_ssh_user "SSH_USER"
      get_provision_on_prem_ssh_password "SSH_PASS"
      get_provision_kinetica_license "LICENSE_KEY"
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
          echo NODE_INFO_JSON "$NODE_INFO_JSON" # debug~~~

          # Get the node's hostname
          get_node_hostname_from_json "$NODE_INFO_JSON" "NODE_HOSTNAME"
          echo "Hostname of the node: $NODE_HOSTNAME" # debug~~~

          # Get the node's IP address
          get_node_ip_from_json "$NODE_INFO_JSON" "NODE_IP"
          echo "IP address of the node: $NODE_IP" # debug~~~

          # Get the node's roles
          get_node_roles_from_json "$NODE_INFO_JSON" "NODE_ROLES"
          echo "Roles of the node: $NODE_ROLES" # debug~~~

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
done # ring loop

################################################################################
################################################################################
################################################################################
################################################################################
################################################################################
# SUPER DEBUG >>>>>

# /opt/gpudb/kagent/bin/kagent --verbose cluster init r1c1 \
#       --infrastructure-provider=onprem --admin-pass="Kinetica1!" \
#       --ssh-user=root --ring=r1 \
#       --connect-via=public_ip_addr --ssh-password=kinetica \
#       --lic-key=zGuPt25a+qro-EsMFFvtYE2XK-s5FMB1jUxBZx-LLNYmBOuP78n-XfPDzOcG8EjcZnA9kgX/lj7Rzdy8DhHU

# /opt/gpudb/kagent/bin/kagent --verbose node init r1c1n1 \
#       "10.0.0.10" r1c1 --roles="head,graph,etcd" --public-ip-addr="10.0.0.10"

# /opt/gpudb/kagent/bin/kagent --verbose node init r1c1n2 \
#       "10.0.0.11" r1c1 --roles="worker" --public-ip-addr="10.0.0.11"

# /opt/gpudb/kagent/bin/kagent --verbose cluster verify r1c1

# /opt/gpudb/kagent/bin/kagent --verbose cluster install r1c1 \
#       --cuda=no --open-firewall-ports=yes --nvidia=no --auto-config=yes

# /opt/gpudb/kagent/bin/kagent --verbose cluster control r1c1 \
#       restart all
