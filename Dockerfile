FROM ubuntu:20.04 AS stage1
ARG NEW_USER
ARG NEW_USER_UID
SHELL ["/bin/bash", "-c"]
RUN if [[ -z $NEW_USER ]]; then echo "NEW_USER must be set" && exit 9; fi

RUN apt update -y

# bsbmainutils for cal/ncal
RUN apt install -y vim less tree bsdmainutils ssh net-tools

# set timezone to Pacific
ENV TZ=America/Los_Angeles
RUN DEBIAN_FRONTEND="noninteractive" apt-get -y install tzdata

FROM stage1 as stage2
ARG NEW_USER
ARG NEW_USER_UID
ARG SSH_PORT=2222
SHELL ["/bin/bash", "-c"]
RUN if [[ -z $NEW_USER ]]; then echo "NEW_USER must be set" && exit 9; fi
RUN if [[ -z $NEW_USER_UID ]]; then echo "NEW_USER_UID must be set" && exit 9; fi
RUN if ! echo $NEW_USER_UID | egrep [0-9]+; then echo "NEW_USER_UID must be a natural number" && exit 9; fi

#set up user
RUN apt install -y sudo apt-utils coreutils
RUN useradd -u $NEW_USER_UID -s /bin/bash -m $NEW_USER && passwd -d $NEW_USER
RUN echo "$NEW_USER" 'ALL=(ALL) NOPASSWD: ALL' >> /etc/sudoers

# enable man through ssh to the docker host
# note that host's authorized_keys must have id_rsa.pub
RUN mkdir -p /home/$NEW_USER/.ssh
RUN chmod 700 /home/$NEW_USER/.ssh

COPY id_rsa.pub /home/$NEW_USER/.ssh/
COPY id_rsa /home/$NEW_USER/.ssh/
RUN chmod 644 /home/$NEW_USER/.ssh/id_rsa.pub
RUN chmod 600 /home/$NEW_USER/.ssh/id_rsa

COPY id_dsa.pub /home/$NEW_USER/.ssh/
COPY id_dsa /home/$NEW_USER/.ssh/
RUN chmod 644 /home/$NEW_USER/.ssh/id_dsa.pub
RUN chmod 600 /home/$NEW_USER/.ssh/id_dsa

# append id_*.pub to authorized_keys
RUN touch /home/$NEW_USER/.ssh/authorized_keys
RUN chmod 600 /home/$NEW_USER/.ssh/authorized_keys
RUN cat /home/$NEW_USER/.ssh/id_dsa.pub >> /home/$NEW_USER/.ssh/authorized_keys
RUN cat /home/$NEW_USER/.ssh/id_rsa.pub >> /home/$NEW_USER/.ssh/authorized_keys

RUN  chown -R $NEW_USER /home/$NEW_USER/.ssh

# install man page via ssh
RUN  mkdir -p /opt/man/bin
SHELL ["/bin/bash", "-c"]
RUN  echo "ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no \\" >> /opt/man/bin/man
RUN  echo "$NEW_USER@172.17.0.1 \\" >> /opt/man/bin/man
RUN  echo '"man" $@' >> /opt/man/bin/man
RUN  chmod +x /opt/man/bin/man
ENV  PATH=/opt/man/bin:$PATH
RUN  echo 'alias man=/opt/man/bin/man' > /etc/profile.d/man-ssh.sh
RUN  echo "Port $SSH_PORT" >> /etc/ssh/sshd_config && echo "" >> /etc/ssh/sshd_config
EXPOSE $SSH_PORT

FROM stage2
ARG NEW_USER
ARG NEW_USER_UID
SHELL ["/bin/bash", "-c"]
RUN if [[ -z $NEW_USER ]]; then echo "NEW_USER must be set" && exit 9; fi

VOLUME ["/home/$NEW_USER"]
WORKDIR /home/$NEW_USER
USER $NEW_USER
ENV USER=$NEW_USER
ENTRYPOINT sudo service ssh restart && /bin/bash
