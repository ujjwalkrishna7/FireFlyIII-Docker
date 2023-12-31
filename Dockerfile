FROM php:7.4-apache

# For more information about fireflyiii/base visit https://dev.azure.com/firefly-iii/BaseImage

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
COPY entrypoint-fpm.sh /usr/local/bin/entrypoint-fpm.sh
COPY counter.txt /var/www/counter-main.txt
COPY date.txt /var/www/build-date-main.txt

ARG version
ENV VERSION=v6.0.23
ENV FIREFLY_III_PATH=/var/www/html

# Install composer
RUN curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer

RUN apt-get update && \
    apt-get install -y git unzip libzip-dev && \
    docker-php-ext-install zip && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

RUN apt-get update && apt-get install -y libicu-dev && \
    docker-php-ext-install bcmath intl


RUN curl -A "Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:109.0) Gecko/20100101 Firefox/111.0" -sSL https://github.com/firefly-iii/firefly-iii/archive/v6.0.23.tar.gz | tar xzC $FIREFLY_III_PATH --strip-components 1 && \
    chmod -R 775 $FIREFLY_III_PATH/storage && \
    composer install --prefer-dist --no-dev --no-scripts && /usr/local/bin/finalize-image.sh

COPY alerts.json /var/www/html/resources/alerts.json

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
