#!/bin/bash

# Start the cron service
service cron start

# Tail the cron log so that logs get output to Docker's log collector
tail -f /var/log/cron.log
