#!/usr/bin/env bash

# Run sshd as a daemon in the background in the docker container
nohup /usr/sbin/sshd -D &

# Set the password as 'kinetica' for the user 'root'
echo -e "kinetica\nkinetica" | passwd root


