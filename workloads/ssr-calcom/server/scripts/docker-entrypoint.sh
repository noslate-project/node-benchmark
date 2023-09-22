#!/bin/bash
# Copyright (C) <2023-2023> Intel Corporation
# SPDX-License-Identifier: MIT

run_flags=$1

# change workdir
cd /calcom/cal.com

# start up postgresql
service postgresql start
sleep 1
# create user ---- sudo -u postgres createuser $POSTGRES_USER -P
# sudo -u postgres psql -c \
#    "CREATE USER unicorn_user WITH SUPERUSER PASSWORD 'magical_password';"

# alter user attributes for creating db
sudo -u postgres psql -c "ALTER USER unicorn_user CREATEDB;"

# Modify the node run flags
file="./apps/web/package.json"
sed -i "s/next start/node $run_flags \/calcom\/cal.com\/node_modules\/next\/dist\/bin\/next start/g" $file

# start cal.com and wait completing
yarn start