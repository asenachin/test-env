#!/usr/bin/bash
set -e # exit immediately if a command exits with a non-zero status.

psql -U postgres -c 'CREATE DATABASE metabase OWNER metabase'
