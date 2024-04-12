#!/usr/bin/bash
set -e # exit if a command exits with a not-zero exit code

psql -U postgres -c "CREATE USER metabase WITH LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOREPLICATION PASSWORD '$METABASE_PASSWORD'"
