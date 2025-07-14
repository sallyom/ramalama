#!/bin/bash
# This script takes a RAG database tag, such as "v100" or "main", and deploys it into
# postgres under a database name that matches the tag. For example, if the requested tag
# is "v100", it expects to find a "v100.dump" in S3. It will download the file and
# restore it to a database of the same name (v100).
#
# In the event that the database already exists, this script will drop the database,
# recreate it, and import the data into the database.
#
# Available options:
# - DROP_ALL_DATABASES: If set to 1, all databases will be dropped before restoring the new database.
# - RELOAD_EXISTING_DATABASE: If set to 1, the existing database will be dropped and reloaded.
# - FORCE_DROP_DATABASES: If set to 1, the databases will be dropped even if they are in use.
# - RAG_DATABASE_TAG: The tag for the database to be deployed (e.g., "v100").
#
# Configuration variables:
# - DB_HOST: The host of the PostgreSQL server.
# - DB_PORT: The port of the PostgreSQL server.
# - DB_USER: The username to connect to the PostgreSQL server.
# - DB_PASSWORD: The password to connect to the PostgreSQL server.
#
set -euxo pipefail

# Use environment variables with defaults
DB_HOST=${DB_HOST:-127.0.0.1}
DB_PORT=${DB_PORT:-5432}
DB_USER=${DB_USER:-postgres}
DB_PASSWORD=${DB_PASSWORD:-postgres}
RAG_DATABASE_TAG=${RAG_DATABASE_TAG:-ragdb}

# Set up database user with password from environment variable
su - postgres -c "psql -c \"ALTER USER ${DB_USER} WITH PASSWORD '${DB_PASSWORD}';\""

# Check to see if we have the required environment variables set.
echo "🔍 Checking for required variables..."
required_vars=(
    "RAG_DATABASE_TAG"
    "DB_HOST"
    "DB_PORT"
    "DB_USER"
    "DB_PASSWORD"
)
for var in "${required_vars[@]}"; do
    if [ -z "${!var}" ]; then
        echo "🚨 Error: ${var} environment variable is not set"
        exit 1
    fi
done

echo "🚚 Deploying RAG database ${RAG_DATABASE_TAG}..."

FORCE_DROP=""
if [ "${FORCE_DROP_DATABASES:-0}" = "1" ]; then
    echo "⚠️ Force drop is enabled. Databases will be dropped even if they are in use."
    FORCE_DROP="WITH (FORCE)"
fi

RAG_DATABASE_FILENAME="ragdb.dump"

echo "🔐 Setting postgres password..."
export PGPASSWORD="${DB_PASSWORD}"

# Get PostgreSQL server version
echo "📊 Checking PostgreSQL server version..."
pg_version=$(psql \
    --host="${DB_HOST}" \
    --port="${DB_PORT}" \
    --username="${DB_USER}" \
    --tuples-only \
    --command="SELECT version();" |
    tr -d ' ')
echo "PostgreSQL server version: ${pg_version}"

# List all databases
echo "📋 Listing all databases..."
databases=$(psql \
    --host="${DB_HOST}" \
    --port="${DB_PORT}" \
    --username="${DB_USER}" \
    --tuples-only \
    --command="SELECT datname FROM pg_database WHERE datistemplate = false;")

if [ "${DROP_ALL_DATABASES:-0}" = "1" ]; then
    echo "🧨 Dropping all databases..."

    # Get a list of all databases, excluding system databases
    databases=$(psql \
        --host="${DB_HOST}" \
        --port="${DB_PORT}" \
        --username="${DB_USER}" \
        --tuples-only \
        --command="SELECT datname FROM pg_database WHERE datistemplate = false AND datname NOT IN ('postgres', 'rdsadmin');")

    # Drop each database
    for db in $databases; do
        echo "🗑️ Dropping database: $db"
        psql \
            --host="${DB_HOST}" \
            --port="${DB_PORT}" \
            --username="${DB_USER}" \
            --command="\set AUTOCOMMIT on" \
            --command="DROP DATABASE IF EXISTS $db ${FORCE_DROP};"
    done
fi

# Check if the database we've been asked to load already exists.
DATABASE_EXISTS=$(echo "${databases}" | grep -q "${RAG_DATABASE_TAG}" && echo "1" || echo "0")

# Database exists but we cannot reload it.
if [[ "${RELOAD_EXISTING_DATABASE:-0}" = "0" ]] && [[ "${DATABASE_EXISTS}" = "1" ]]; then
    echo "🛑 Database '${RAG_DATABASE_TAG}' exists, but we cannot reload it"
    echo "☝️ Please set RELOAD_EXISTING_DATABASE to 1 to force a reload."
    exit 0
fi

# Database exists and we were asked to reload it.
if [[ "${RELOAD_EXISTING_DATABASE:-0}" = "1" ]] && [[ "${DATABASE_EXISTS}" = "1" ]]; then
    echo "🧽 Cleaning up the old database"
    psql \
        --host="${DB_HOST}" \
        --port="${DB_PORT}" \
        --username="${DB_USER}" \
        --command="\set AUTOCOMMIT on" \
        --command="DROP DATABASE IF EXISTS ${RAG_DATABASE_TAG} ${FORCE_DROP};"
fi

# Database does not exist, so let's load it.
if [[ "${DATABASE_EXISTS}" = "0" ]]; then
    echo "🚀 Restoring the database from ${RAG_DATABASE_FILENAME}..."
    psql \
        --host="${DB_HOST}" \
        --port="${DB_PORT}" \
        --username="${DB_USER}" \
        --command="\set AUTOCOMMIT on" \
        --command="CREATE DATABASE ${RAG_DATABASE_TAG};"
    pg_restore -vvv \
        --host="${DB_HOST}" \
        --port="${DB_PORT}" \
        --username="${DB_USER}" \
        --dbname="${RAG_DATABASE_TAG}" \
        "/tmp/${RAG_DATABASE_FILENAME}"
fi

echo "🎉 Done at $(date)"

