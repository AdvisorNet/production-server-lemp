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
HOSTSNAME='/etc/hosts'
DRUPALVER='7'
LOGFILE='/tmp/install.log'

## START OF CODE ##
if ! [[ "${HOSTNAME}" == *\.* ]]; then
        HOSTS=`cat ${HOSTSNAME} | grep -v "^#" | grep -v "^127\.0\.0\.1" | cut -f2 -d$'\t'`
        IFS=' ' read -a HOST <<< "${HOSTS}"
        for i in "${HOST[@]}"
        do
                if [[ "${i}" == *\.* ]]; then
                        HOSTNAME=${i}
                fi
        done
fi


USERNAME=`sed -e 's/\.//g' <<<$HOSTNAME`

clear
echo -e "Changed hostname to ${RED}${HOSTNAME}${WHITE}"
echo -e "Hostname set to ${BLUE}${HOSTNAME} ${WHITE}"
echo -e "Username set to ${BLUE}${USERNAME} ${WHITE}"
echo -e "We are about to install Drupal ${BLUE}V7${WHITE} to ${BLUE}${HOSTPATH}/$HOSTNAME ${WHITE}"
echo 
echo -e "I am writing all output from apt-get to ${RED}${LOGFILE}${WHITE} to keep the screen clear for errors"
echo 
read -p "Are you happy with these settings? [y/n] " -n 1 -r
echo    
if [[ ! $REPLY =~ ^[Yy]$ ]]
then
    exit 1
fi


#Set the timezone
rm -f /etc/localtime
ln -s /usr/share/zoneinfo/UTC /etc/localtime

# Install required software
apt-get update &>${LOGFILE}
apt-get install -y php5-fpm nginx php5 php5-gd git ntp &>${LOGFILE}

# Install and configure mysql
apt-get install -y debconf-utils &>${LOGFILE}
debconf-set-selections <<< "mysql-server mysql-server/root_password password ${SQLROOTPASSWD}"
debconf-set-selections <<< "mysql-server mysql-server/root_password_again password ${SQLROOTPASSWD}"
apt-get -y install mysql-server &>${LOGFILE}

# Start services at boot
update-rc.d php5-fpm defaults &>${LOGFILE}
update-rc.d mysql defaults &>${LOGFILE}
update-rc.d nginx defaults &>${LOGFILE}

# Create the full path for our web visible folder
mkdir ${HOSTPATH}/${HOSTNAME} -p

#Add the user and set the password
adduser ${USERNAME} --home ${HOSTPATH}/${HOSTNAME} --disabled-login --gecos "nginx site user" --no-create-home  &>${LOGFILE}
echo "${USERNAME}:${PASSWD}" | chpasswd &>${LOGFILE}

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
/usr/bin/mysql -uroot -p${SQLROOTPASSWD} -e "$SQL" &>${LOGFILE}

# Install Drupal
apt-get install -y drush &>${LOGFILE}
cd /var/www/vhosts/${HOSTNAME}
drush dl drupal-${DRUPALVER}
DRUPALDIR=`ls | grep drupal`
mv ${DRUPALDIR}/* .
rm -fr ${DRUPALDIR}
drush site-install standard --account-name=admin --account-pass=admin --db-url=mysql://${DRUPALUSERNAME}:${DRUPALPASSWD}@localhost/${DRUPALDATABASE} -y
#cd sites/default
#cp default.settings.php settings.php
#cp default.services.yml services.yml

# Set ownership on the web folder
chown -R ${USERNAME}.www-data ${HOSTPATH}/${HOSTNAME}

#Enable SFTP
sed -i -e 's/Subsystem sftp/#Subsystem\tsftp/g' /etc/ssh/sshd_config
echo "Subsystem sftp    internal-sftp" >>/etc/ssh/sshd_config
service ssh restart

# Output Configuration Details
echo -e "${BLUE}Now go to ${HOSTNAME} to finish off configuring Drupal${WHITE}"
echo "Use these settings"
echo "MySQL username = ${DRUPALUSERNAME}"
echo "MySQL database = ${DRUPALDATABASE}"
echo "MySQL password = ${DRUPALPASSWD}"
echo " "
echo "MYSQL Root Password = ${SQLROOTPASSWD}"
echo " "
echo "System username = ${USERNAME}"
echo "System user password = ${PASSWD}"
