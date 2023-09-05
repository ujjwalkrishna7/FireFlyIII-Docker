#!/bin/bash

echo "Now in entrypoint.sh for Firefly III"
echo ""
echo "Script:            1.1.0 (2023-06-03)"
echo "User:              $(whoami)"
echo "Group:             $(id -g -n)"
echo "Working dir:       $(pwd)"
echo "Base build number: $BASE_IMAGE_BUILD"
echo "Base build date:   $BASE_IMAGE_DATE"
echo "Build number:      $(cat /var/www/counter-main.txt)"
echo "Build date:        $(cat /var/www/build-date-main.txt)"


#
# Echo with [i]
#
function infoLine () { 
        echo "  [i] $1"
}
#
# Echo with [✓]
#
function positiveLine () { 
        echo "  [✓] $1"
}

#
# echo with [!]
#
function warnLine () { 
        echo "  [!] $1"
}

# https://github.com/docker-library/wordpress/blob/master/docker-entrypoint.sh
# usage: file_env VAR [DEFAULT]
#    ie: file_env 'XYZ_DB_PASSWORD' 'example'
# (will allow for "$XYZ_DB_PASSWORD_FILE" to fill in the value of
#  "$XYZ_DB_PASSWORD" from a file, especially for Docker's secrets feature)
file_env() {
	local var="$1"
	local fileVar="${var}_FILE"
	local def="${2:-}"
	if [ "${!var:-}" ] && [ "${!fileVar:-}" ]; then
		echo >&2 "error: both $var and $fileVar are set (but are exclusive)"
		exit 1
	fi
	local val="$def"
	if [ "${!var:-}" ]; then
		val="${!var}"
	elif [ "${!fileVar:-}" ]; then
		val="$(< "${!fileVar}")"
	fi
	export "$var"="$val"
	unset "$fileVar"
}

# envs that can be appended with _FILE
envs=(
	SITE_OWNER
	APP_KEY
	DB_CONNECTION
	DB_HOST
	DB_PORT
	DB_DATABASE
	DB_USERNAME
	DB_PASSWORD
	PGSQL_SSL_MODE
	PGSQL_SSL_ROOT_CERT
	PGSQL_SSL_CERT
	PGSQL_SSL_KEY
	PGSQL_SSL_CRL_FILE
	REDIS_HOST
	REDIS_PASSWORD
	REDIS_PORT
	COOKIE_DOMAIN
	MAIL_DRIVER
	MAIL_HOST
	MAIL_PORT
	MAIL_FROM
	MAIL_USERNAME
	MAIL_PASSWORD
	MAIL_ENCRYPTION
	MAILGUN_DOMAIN
	MAILGUN_SECRET
	MAILGUN_ENDPOINT
	MANDRILL_SECRET
	SPARKPOST_SECRET
	MAPBOX_API_KEY
	FIXER_API_KEY
	LOGIN_PROVIDER
	WINDOWS_SSO_ENABLED
	WINDOWS_SSO_DISCOVER
	WINDOWS_SSO_KEY
	TRACKER_SITE_ID
	TRACKER_URL
	STATIC_CRON_TOKEN
  PASSPORT_PRIVATE_KEY
  PASSPORT_PUBLIC_KEY
)

for e in "${envs[@]}"; do
  file_env "$e"
done

# touch DB file
if [[ $DKR_CHECK_SQLITE != "false" ]]; then
  if [[ $DB_CONNECTION == "sqlite" ]]; then
    touch $FIREFLY_III_PATH/storage/database/database.sqlite
    infoLine "Touched DB file for SQLite"
  fi
fi

composer dump-autoload
php artisan package:discover

infoLine "Current working dir is '$(pwd)'"
infoLine "Wait for the database. You may see an error about an 'aborted connection', this is normal."
if [[ -z "$DB_PORT" ]]; then
  if [[ $DB_CONNECTION == "pgsql" ]]; then
    DB_PORT=5432
  elif [[ $DB_CONNECTION == "mysql" ]]; then
    DB_PORT=3306
  fi
fi
if [[ -n "$DB_PORT" ]]; then
  /usr/local/bin/wait-for-it.sh "${DB_HOST}:${DB_PORT}" -t 60 -- echo "  [✓] DB is up."
fi

infoLine "Wait another 10 seconds in case the DB needs to boot."
sleep 10
positiveLine "Done waiting for the DB to boot."

if [[ $DKR_BUILD_LOCALE == "true" ]]; then
  infoLine "Will rebuild all locales..."
  locale-gen
fi

if [[ $DKR_RUN_MIGRATION == "false" ]]; then
  warnLine "Will NOT run migration commands."
else
  php artisan firefly-iii:create-database
fi

infoLine "Current working dir is '$(pwd)'"

# there are 13 upgrade commands
if [[ $DKR_RUN_UPGRADE == "false" ]]; then
  warnLine 'Will NOT run upgrade commands.'
else
  php artisan firefly-iii:upgrade-database
fi

# there are 15 verify commands
if [[ $DKR_RUN_VERIFY == "false" ]]; then
  warnLine 'Will NOT run verification commands.'
else
  php artisan firefly-iii:correct-database 
fi

# report commands
if [[ $DKR_RUN_REPORT == "false" ]]; then
  warnLine 'Will NOT run report commands.'
else
  php artisan firefly-iii:report-integrity
fi

if [[ $DKR_RUN_PASSPORT_INSTALL == "false" ]]; then
  warnLine 'Will NOT generate new OAuth keys.'
else
  php artisan passport:install
fi

php artisan firefly-iii:set-latest-version --james-is-cool
php artisan cache:clear > /dev/null 2>&1
php artisan config:cache > /dev/null 2>&1

# set docker var.
export IS_DOCKER=true

php artisan firefly-iii:verify-security-alerts
php artisan firefly:instructions install

if [ -z $APACHE_RUN_USER ]
then
      APACHE_RUN_USER='www-data'
fi

if [ -z $APACHE_RUN_GROUP ]
then
      APACHE_RUN_GROUP='www-data'
fi

rm -rf $FIREFLY_III_PATH/storage/framework/cache/data/*
rm -f $FIREFLY_III_PATH/storage/logs/*.log
chown -R $APACHE_RUN_USER:$APACHE_RUN_GROUP $FIREFLY_III_PATH/storage
chmod -R 775 $FIREFLY_III_PATH/storage

echo ""
warnLine "You can safely ignore the error about the 'fully qualified domain name'."
echo ""
exec apache2-foreground
