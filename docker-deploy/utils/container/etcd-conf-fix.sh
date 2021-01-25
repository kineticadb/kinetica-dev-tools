#!/usr/bin/env bash

find /opt/gpudb/kagent/resources/etcd_gpudb_conf.yml -type f -exec sed -i.bak -e 's/become: yes/# become: yes/g; s/become_user: gpudb/# become_user: gpudb/g' {} \;
find /opt/gpudb/kagent/resources/roles/etcd/ -type f -exec sed -i.bak -e 's/become: yes/# become: yes/g; s/become_user: gpudb/# become_user: gpudb/g' {} \;
find /opt/gpudb/kagent/resources/roles/etcd/tasks/add_member.yml -type f -exec sed -i.bak -e 's|systemd:|shell: /opt/gpudb/etcd/gpudb-etcd.sh stop|g' {} \;
find /opt/gpudb/kagent/resources/roles/etcd/tasks/add_member.yml -type f -exec sed -i.bak -e 's/name: kinetica-etcd/# name: kinetica-etcd/g; s/state:/# state:/g' {} \;
