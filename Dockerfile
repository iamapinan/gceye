FROM wordpress:5.8-php7.4-apache

WORKDIR /var/www/html

RUN apt-get update
RUN apt-get -y install libldb-dev libldap2-dev && docker-php-ext-install pdo_mysql ldap