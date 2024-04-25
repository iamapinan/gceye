FROM optiz0r/wordpress-ldap:6.5.0-php8.2-apache

WORKDIR /var/www/html

RUN apt-get update
RUN apt-get -y install libldb-dev libldap2-dev && docker-php-ext-install pdo_mysql ldap
