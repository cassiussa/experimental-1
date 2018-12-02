export USER_ID=$(id -u)
export GROUP_ID=$(id -g)
envsubst < ${HOME}/passwd.template > /tmp/passwd
export LD_PRELOAD=libnss_wrapper.so
export NSS_WRAPPER_PASSWD=/tmp/passwd
export NSS_WRAPPER_GROUP=/etc/group

cp -f /tmp/passwd /etc/passwd

echo ${USER_ID}
echo ${GROUP_ID}
whoami

/usr/sbin/httpd -D FOREGROUND -f /etc/httpd/conf/httpd.conf


