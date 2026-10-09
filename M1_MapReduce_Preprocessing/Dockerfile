FROM apache/hadoop:3.4.1
USER root
RUN sed -i 's|^mirrorlist=|#mirrorlist=|g' /etc/yum.repos.d/*.repo && \
    sed -i 's|^#baseurl=http://mirror.centos.org/centos|baseurl=http://vault.centos.org/centos|g' /etc/yum.repos.d/*.repo && \
    yum install -y python3 && \
    ln -sf /usr/bin/python3 /usr/bin/python3
USER hadoop
