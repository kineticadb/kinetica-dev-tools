FROM centos:centos7

ARG USER="dd-user"

WORKDIR /home/

# Ensure current user and 'gpudb' user exist
RUN useradd ${USER}
RUN useradd gpudb

ADD utils/ utils/
# ADD packages/ packages/

# Install OpenSSH server, client etc. and create keys for ssh as necessary
# RUN yum install -y openssh openssh-server openssh-clients openssl-libs
RUN yum install -y openssh openssh-server openssh-clients openssl-libs openssl &&\
    ssh-keygen -q -N "" -t dsa -f /etc/ssh/ssh_host_ecdsa_key &&\
    ssh-keygen -q -N "" -t rsa -f /etc/ssh/ssh_host_rsa_key  &&\
    ssh-keygen -A

# Install useful packages
RUN yum install -y wget vim less lsof gcc-c++ python-pip python-devel maven

# Important database ports
EXPOSE 8080 8088 9049 9050 9191

# Run the SSH server and then make sure the container does not exit
CMD chmod +x utils/container/docker-sshd-setup.sh &&\
    utils/container/docker-sshd-setup.sh &&\
    tail -f /dev/null