FROM centos:centos7

ARG RPM

WORKDIR /home/
RUN mkdir config

ADD utils/ utils/
ADD packages/ packages/

# Install OpenSSH server, client etc. and create keys for ssh as necessary
RUN yum install -y openssh openssh-server openssh-clients openssl-libs openssl &&\
    ssh-keygen -q -N "" -t dsa -f /etc/ssh/ssh_host_ecdsa_key &&\
    ssh-keygen -q -N "" -t rsa -f /etc/ssh/ssh_host_rsa_key  &&\
    ssh-keygen -A

# Install useful packages
RUN yum install -y wget vim less lsof epel-release
RUN yum install -y python-pip jq

# Setup yq (2.11.1)
RUN pip install yq 

# Install KAgent
RUN yum install -y packages/${RPM}

EXPOSE 8081

# Run the SSH server and then make sure the container does not exit
CMD chmod +x utils/container/docker-sshd-setup.sh &&\
    utils/container/docker-sshd-setup.sh &&\
    /etc/init.d/kagent_ui start &&\
    tail -f /dev/null