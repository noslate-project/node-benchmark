#!/bin/bash
# Copyright (C) <2023-2023> Intel Corporation
# SPDX-License-Identifier: MIT


cd /calcom

# start up postgresql
service postgresql start

# create user
# sudo -u postgres createuser $POSTGRES_USER -P
sudo -u postgres psql -c \
    "CREATE USER unicorn_user WITH SUPERUSER PASSWORD 'magical_password';"

# alter user attributes for creating db
sudo -u postgres psql -c "ALTER USER unicorn_user CREATEDB;"