FROM centos7

LABEL Maintainer="Cassius John-Adams <cassius.s.adams@gmail.com>"

ENV HOME /var/www/html/
ENV KUBECONFIG /var/www/html/.kube/config

# Install Apache webserver, no docs, then cleanup right away
RUN yum install epel-release -y && \
    yum install httpd wget jq python-pip nss_wrapper gettext openssh -y && \
    yum clean all && \
    pip install httpie

# Copy the index.html file (a bash script) and css style into the cgi-bin
COPY ["index.html", "style.css", "/var/www/cgi-bin/"]
COPY ["account_setup.sh", "/var/www/cgi-bin/"]
COPY ["gitlab_setup.sh", "/var/www/cgi-bin/"]
COPY ["passwd.template", "/var/www/html/"]
COPY ["fix-script.sh", "/tmp/"]

# Perform some updates to the httpd.conf, set up ownerships, and push logs to stdout and stderr
RUN sed -i "s/#AddHandler cgi-script .cgi/AddHandler cgi-script .html/g" /etc/httpd/conf/httpd.conf && \
    sed -i "/ScriptAlias /c\     ScriptAlias \/ \"\/var\/www\/cgi-bin\/\" " /etc/httpd/conf/httpd.conf && \
    sed -i "s/Listen 80/Listen 8080/g" /etc/httpd/conf/httpd.conf && \
    echo "LoadModule cgid_module modules/mod_cgid.so" >> /etc/httpd/conf/httpd.conf && \
    echo "LoadModule env_module modules/mod_env.so" >> /etc/httpd/conf/httpd.conf && \ 
    echo "PassEnv OKD_USERNAME OKD_PASSWORD" >> /etc/httpd/conf/httpd.conf && \
# Command line tool
    wget https://github.com/openshift/origin/releases/download/v3.11.0/openshift-origin-client-tools-v3.11.0-0cbc58b-linux-64bit.tar.gz && \
    tar -xvzf openshift-origin-client-tools-v3.11.0-0cbc58b-linux-64bit.tar.gz && \
    rm -rf openshift-origin-client-tools-v3.11.0-0cbc58b-linux-64bit.tar.gz && \
    mv openshift-origin-client-tools-v3.11.0-0cbc58b-linux-64bit/oc /usr/local/bin && \
    mv openshift-origin-client-tools-v3.11.0-0cbc58b-linux-64bit/kubectl /usr/local/bin && \
    rm -rf openshift-origin-client-tools-v3.11.0-0cbc58b-linux-64bit && \
    mkdir /var/www/html/.kube/ && \
    touch /var/www/html/.kube/config && \
    chmod -R 755 /var/www/html && \
    chown -R apache /var/www/cgi-bin && \
    chmod -R 755 /var/www/cgi-bin && \
    chgrp -R 0 /var/www && chmod -R g=u /var/www && \
    chgrp -R 0 /usr/local/etc && chmod -R g=u /usr/local/etc && \
    chgrp -R 0 /run/httpd  && chmod -R g=u /run/httpd && \
    chgrp -R 0 /etc/httpd/logs  && chmod -R g=u /etc/httpd/logs && \
    ln -sf /dev/stdout /var/log/httpd/access_log && \
    ln -sf /dev/stderr /var/log/httpd/error_log && \
    chmod g+w /etc/passwd
    
WORKDIR /var/www/html/

EXPOSE 8080
USER 1001

# Start up apapche and specify the configuration location
#ENTRYPOINT ["/usr/sbin/httpd"]
CMD ["/usr/sbin/httpd", "-D", "FOREGROUND", "-f", "/etc/httpd/conf/httpd.conf", "&&", "bash", "/tmp/fix-script.sh"]

