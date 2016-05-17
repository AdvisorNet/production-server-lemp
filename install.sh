#!/bin/bash
TZ='Europe/London'
HOSTNAME=`hostname`
RED='\033[31m'
WHITE="\033[0m"
BLUE='\033[00;34m'
PASSWD=`< /dev/urandom tr -dc _A-Z-a-z-0-9 | head -c${1:-12}`
DRUPALPASSWD=${PASSWD}
SQLROOTPASSWD=${PASSWD}
FPMPATH='/etc/php5/fpm/pool.d'
HOSTPATH="/var/www/vhosts"
NGINXPATH='/etc/nginx/sites-available'
MYSQL=`which mysql`
DRUPALDATABASE='drupal'
DRUPALUSERNAME='drupal'
HOSTNAME=`hostname`
USERNAME=`sed -e 's/\.//g' <<<$HOSTNAME`

## START OF CODE ##

echo -e "${BLUE}Hostname set to ${HOSTNAME} ${WHITE}"
echo -e "${BLUE}Username set to ${USERNAME} ${WHITE}";

#Set the timezone
rm -f /etc/localtime
ln -s /usr/share/zoneinfo/UTC /etc/localtime

# Install required software
apt-get update
apt-get install -y php5-fpm nginx php5 php5-gd git ntp

# Install and configure mysql
printf "${RED}Setting SQLROOTPASSWD to ${SQLROOTPASSWD}${WHITE}"
apt-get install -y debconf-utils
debconf-set-selections <<< "mysql-server mysql-server/root_password password ${SQLROOTPASSWD}"
debconf-set-selections <<< "mysql-server mysql-server/root_password_again password ${SQLROOTPASSWD}"
apt-get -y install mysql-server

# Start services at boot
update-rc.d php5-fpm defaults
update-rc.d mysql defaults
update-rc.d nginx defaults

# Create the full path for our web visible folder
mkdir ${HOSTPATH}/${HOSTNAME} -p

#Add the user and set the password
adduser ${USERNAME} --home ${HOSTPATH}/${HOSTNAME} --disabled-login --gecos "nginx site user" --no-create-home #>/dev/null
echo "${USERNAME}:${PASSWD}" | chpasswd

# Move the default php-fpm daemon out of the way,  save memory
mv ${FPMPATH}/www.conf ${FPMPATH}/www.conf.orig

# Create our php-fpm file
echo "[${HOSTNAME}]" >${FPMPATH}/${HOSTNAME}.conf
echo "user =  ${USERNAME}" >>${FPMPATH}/${HOSTNAME}.conf
echo "group = ${USERNAME}" >>${FPMPATH}/${HOSTNAME}.conf
echo "listen = /var/run/php-fpm-${HOSTNAME}.sock" >>${FPMPATH}/${HOSTNAME}.conf
echo "listen.owner = ${USERNAME}" >>${FPMPATH}/${HOSTNAME}.conf
echo "listen.group = www-data" >>${FPMPATH}/${HOSTNAME}.conf

echo "pm = dynamic
pm.max_children = 50
pm.start_servers = 20
pm.min_spare_servers = 10
pm.max_spare_servers = 20
pm.max_requests = 500" >>${FPMPATH}/${HOSTNAME}.conf

# Configure nginx and restart
echo "server {
        listen   80;
        server_name $HOSTNAME;
        root ${HOSTPATH}/$HOSTNAME;
        index index.php;

        location / {
                try_files \$uri /index.php?\$query_string; # For Drupal >= 7
        }

        location @rewrite {
                rewrite ^/(.*)$ /index.php?q=\$1;
        }


        error_page 404 /404.html;
        error_page 500 502 503 504 /50x.html;
        location = /50x.html {
                root /usr/share/nginx/html/drupal;
        }
        location ~ \.php$ {
                fastcgi_index index.php;
                include fastcgi_params;
                fastcgi_pass unix:/var/run/php-fpm-${HOSTNAME}.sock;
        }
}" > ${NGINXPATH}/${HOSTNAME}.conf


ln -s /etc/nginx/sites-available/${HOSTNAME}.conf /etc/nginx/sites-enabled/${HOSTNAME}.conf

service nginx restart


# Create a database for Drupal
CMD1="CREATE DATABASE IF NOT EXISTS ${DRUPALDATABASE};"
CMD2="GRANT USAGE ON ${DRUPALDATABASE}.* TO ${DRUPALUSERNAME}@localhost IDENTIFIED BY '${DRUPALPASSWD}';"
CMD3="GRANT ALL PRIVILEGES ON ${DRUPALDATABASE}.* TO ${DRUPALUSERNAME}@localhost;"
CMD4="FLUSH PRIVILEGES;"

SQL="${CMD1}${CMD2}${CMD3}${CMD4}"

/usr/bin/mysql -uroot -p${SQLROOTPASSWD} -e "$SQL"


#### Ignore this for my test server only.
#### TEST PASSWORD IS t0bAeV0VnW0o

# Install Drupal
apt-get install -y drush
cd /var/www/vhosts/${HOSTNAME}
drush dl drupal-8
DRUPALDIR=`ls | grep drupal`
mv ${DRUPALDIR}/* .
rm -fr ${DRUPALDIR}
cd sites/default
cp default.settings.php settings.php
cp default.services.yml services.yml
# Set ownership on the web folder
chown -R ${USERNAME}.www-data ${HOSTPATH}/${HOSTNAME}


echo "Now go to ${HOSTNAME} to finish off configuring Drupal"
echo "Use these settings"
echo "MySQL username = ${DRUPALUSERNAME}"
echo "MySQL database = ${DRUPALDATABASE}"
echo "MySQL password = ${DRUPALPASSWD}"
echo " "
echo "MYSQL Root Password = ${SQLROOTPASSWD}"
echo " "
echo "System username = ${USERNAME}"
echo "System user password = ${PASSWD}"
