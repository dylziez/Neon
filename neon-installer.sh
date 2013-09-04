#!/bin/bash

mkdir ~/neon-install/
cd ~/neon-install/
touch ~/neon-install/install.log
exec 3>&1 > ~/neon-install/install.log 2>&1

############################################################
# Functions
############################################################

function status {
	echo $1;
	echo $1 >&3
}

function install {
	DEBIAN_FRONTEND=noninteractive apt-get -q -y install "$1"
	apt-get clean
}

function remove {
	/etc/init.d/"$1" stop
	service "$1" stop
	export DEBIAN_PRIORITY=critical
	export DEBIAN_FRONTEND=noninteractive
	apt-get -q -y remove "$1"
	apt-get clean
}

function slaughter_httpd {
	pkill apache
	pkill apache2
	aptitude -y purge ~i~napache
	apt-get --purge -y autoremove apache*
	apt-get remove apache2-utils
	
	kill -9 $( lsof -i:80 -t )
	x=$(($x + 1));
	
	update-rc.d -f apache2 remove
	update-rc.d -f apache remove
	update-rc.d -f nginx remove
	update-rc.d -f lighttpd remove
	update-rc.d -f httpd remove
}

function check_installs {
	if ! type -p $1 > /dev/null; then
		status "Unfortunately $1 failed to install. Neon install aborting."
		exit 1
	fi
}

function check_sanity {
	# Do some sanity checking.
	if [ $(/usr/bin/id -u) != "0" ]
	then
		status "Neon must be installed as root. Please log in as root and try again."
		die 'Neon must be installed as root. Please log in as root and try again.'
	fi

	if [ ! -f /etc/debian_version ]
	then
		status "Neon must be installed as root. Please log in as root and try again."
		die "Neon must be installed on Debian 6.0."
	fi
}

function die {
	echo "ERROR: $1" > /dev/null 1>&2
	exit 1
}

check_sanity


############################################################
# Begin Installation
############################################################

status "====================================="
status "     Welcome to Neon Installation"
status "====================================="
status "Neon will remove any existing apache,"
status "nginx, mysql or php services you have"
status "installed on this server. It will"
status "also delete all custom config files"
status "that you may have."
status " "
status "It is reccomended that you run this"
status "installer in a screen."
status " "
status "This script will begin installing"
status "Neon in 10 seconds. If you wish to"
status "cancel the install press CTRL + C"
sleep 10
status "Neon needs a bit of information before"
status "beginning the installation."
status " "
status "What hostname would you like to use (Example: server.yourdomain.com):"
read user_host

############################################################
# Begin Cleanup
############################################################

status " "
status "Begining cleanup..."

remove="apache2 apache* apache2* apache2-utils mysql* php* nginx lighttpd httpd* php5-fpm vsftpd proftpd exim qmail postfix sendmail"

slaughter_httpd
status "Cleanup Phase: 1 of 17"

for program in $remove
do
	remove $program
	x=$(($x + 1));
	status "Cleanup Phase: $x of 17"
done
apt-get autoremove

status " "
status "Cleanup completed."
status "Beginning installation phase 1 of 2"

############################################################
# Begin Install Phase 1
############################################################

echo "deb http://repo.neoncp.com/dotdeb stable all" >> /etc/apt/sources.list
wget http://repo.neoncp.com/dotdeb/dotdeb.gpg
cat dotdeb.gpg | apt-key add -
rm -rf dotdeb.gpg
apt-get update
y=$(($y + 1));
status "Install: $y of 32"

install="nginx php5 vim openssl php5-mysql zip unzip sqlite3 php-mdb2-driver-mysql php5-sqlite php5-curl php-pear php5-dev acl libcurl4-openssl-dev php5-gd php5-imagick php5-imap php5-mcrypt php5-xmlrpc php5-xsl php5-fpm libpcre3-dev build-essential php-apc git-core pdns-server pdns-backend-mysql host mysql-server phpmyadmin"

for program in $install
do
	install $program
	y=$(($y + 1));
	status "Install: $y of 32"
done

############################################################
# Perform Installation Checks
############################################################

check_installs nginx
check_installs php
check_installs git
check_installs mysql

############################################################
# Begin Configuration Phase 1
############################################################

status " "
status "Begining Configuration Phase: 1 of 2"

/etc/init.d/mysql stop
invoke-rc.d mysql stop
/etc/init.d/nginx stop
/etc/init.d/php5-fpm stop
status "Base Config: 1 / 11"

############################################################
# Download Neon
############################################################

mkdir /var/neon/
git clone -b develop-mail https://github.com/BlueVM/Neon.git /var/neon/

cd ~/neon-install/
status "Base Config: 2 / 11"

############################################################
# Create Folders
############################################################

touch /var/neon/data/log.txt
mkdir /var/neon/neonpanel/uploads
mkdir /var/neon/neonpanel/downloads
mkdir /home/root/

cd ~/neon-install/
status "Base Config: 3 / 11"

############################################################
# Generate Passwords
############################################################

mysqlpassword=`< /dev/urandom tr -dc A-Z-a-z-0-9 | head -c${1:-32};`

cd ~/neon-install/
status "Base Config: 4 / 11"

############################################################
# Create Neon Configs
############################################################

cp /var/neon/data/config.example /var/neon/data/config.json
sed -i 's/databaseusernamehere/root/g' /var/neon/data/config.json
sed -i 's/databasepasswordhere/'${mysqlpassword}'/g' /var/neon/data/config.json
sed -i 's/databasenamehere/panel/g' /var/neon/data/config.json
sed -i 's/randomlygeneratedsalthere/'${salt}'/g' /var/neon/data/config.json
sed -i 's/hostnameforinstallhere/'${user_host}'/g' /var/neon/data/config.json

ssh-keygen -t rsa -N "" -f ~/neon-install/id_rsa
mkdir ~/.ssh/
cat id_rsa.pub >> ~/.ssh/authorized_keys
mv id_rsa /var/neon/data/
setfacl -Rm user:www-data:rwx /var/neon/*

cd ~/neon-install/
status "Base Config: 5 / 11"

############################################################
# Begin Mysql Configuration
############################################################

mv /etc/my.cnf /etc/my.cnf.backup
cp /var/neon/neonpanel/includes/configs/my.cnf /etc/my.cnf
/etc/init.d/mysql start

salt=`< /dev/urandom tr -dc A-Z-a-z-0-9 | head -c${1:-32};`
mysqladmin -u root password $mysqlpassword

while ! mysql -u root -p$mysqlpassword  -e ";" ; do
       status "Unfortunatly mysql failed to install correctly. Neon installation aborting (Error #2)".
done

mysql -u root --password="$mysqlpassword" --execute="CREATE DATABASE IF NOT EXISTS panel;CREATE DATABASE IF NOT EXISTS dns;"
mysql -u root --password="$mysqlpassword" panel < /var/neon/data.sql

cd ~/neon-install/
status "Base Config: 6 / 11"

############################################################
# Begin PHP Configuration
############################################################

cp /var/neon/neonpanel/includes/configs/php.conf /etc/php5/fpm/pool.d/www.conf
mv /etc/php5/conf.d/apc.ini /etc/php5/apc.old
rm -rf /etc/php5/fpm/php.ini
cp /var/neon/neonpanel/includes/configs/php.ini /etc/php5/fpm/php.ini

cd ~/neon-install/
status "Base Config: 7 / 11"

############################################################
# Begin SSL Configuration
############################################################

mkdir /usr/ssl
cd /usr/ssl
openssl genrsa -out neon.key 1024
openssl rsa -in neon.key -out neon.pem
openssl req -new -key neon.pem -subj "/C=US/ST=Oregon/L=Portland/O=IT/CN=www.neonpanel.com" -out neon.csr
openssl x509 -req -days 365 -in neon.csr -signkey neon.pem -out neon.crt

cd ~/neon-install/
status "Base Config: 8 / 11"

############################################################
# Begin Nginx Configuration
############################################################

rm -rf /etc/nginx/sites-enabled/* 
mv /var/neon/neonpanel/includes/configs/nginx.neon.conf /etc/nginx/sites-enabled/nginx.neon.conf 
setfacl -Rm user:www-data:rwx /var/neon/*

cd ~/neon-install/
status "Base Config: 9 / 11"

############################################################
# Begin PHPMyAdmin Configuration
############################################################

mv /etc/phpmyadmin/config.inc.php /etc/phpmyadmin/config.old.inc.php
cp /var/neon/neonpanel/includes/configs/pma.php /usr/share/phpmyadmin/
cp /var/neon/neonpanel/includes/configs/pma.config.inc.php /etc/phpmyadmin/config.inc.php
sed -i 's/databasepasswordhere/'${mysqlpassword}'/g' /usr/share/phpmyadmin/pma.php

cd ~/neon-install/
status "Base Config: 10 / 11"

############################################################
# Begin PDNS Configuration
############################################################

mv /etc/powerdns/pdns.conf /etc/powerdns/pdns.old
cp /var/neon/neonpanel/includes/configs/pdns.conf /etc/powerdns/pdns.conf
sed -i 's/databasenamehere/dns/g' /etc/powerdns/pdns.conf
sed -i 's/databasepasswordhere/'${mysqlpassword}'/g' /etc/powerdns/pdns.conf
sed -i 's/databaseusernamehere/root/g' /etc/powerdns/pdns.conf

cd ~/neon-install/
status "Base Config: 11 / 11"

############################################################
# Begin Clean Up
############################################################

status "Finishing and cleaning up..."
aptitude -y purge ~i~napache
/etc/init.d/nginx start
/etc/init.d/pdns start
/etc/init.d/php5-fpm start
cd /var/neon/neonpanel/
php init.php
rm -rf init.php
cd ~/neon-install/
(crontab -l 2>/dev/null; echo "* * * * * sh /var/neon/data/scripts/stats.sh") | crontab -
ipaddress=`ifconfig  | grep 'inet addr:'| grep -v '127.0.0.1' | grep -v '127.0.0.2' | cut -d: -f2 | awk '{ print $1}'`;
mysql -u root --password="$mysqlpassword" --execute="UPDATE panel.settings SET setting_value='$ipaddress' WHERE id='5';"
wget --delete-after http://www.neoncp.com/installer/report.php?ip=$ipaddress

status "=========NEON_INSTALL_COMPLETE========"
status "Mysql Root Password: $mysqlpassword"
status "You can now login at https://$ipaddress:2026"
status "Username: root"
status "Password: your_root_password"
status "====================================="
status "It is reccomended you download the"
status "log ~/neon-install/neon-install.log"
status "and then delete it from your system."
