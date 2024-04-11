FROM postgres:16.2
MAINTAINER Krisztian Szabo <krisz@schemamap.io>

COPY ./init_schemamap.sh /docker-entrypoint-initdb.d/0000000000_init_schemamap.sh

COPY ./*.sql /schemamap/
