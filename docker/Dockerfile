FROM postgres:16.2
MAINTAINER Krisztian Szabo <krisz@schemamap.io>

COPY ./init_schemamap.sh /schemamap/init_schemamap.sh
COPY ./*.sql /schemamap/

# https://github.com/docker-library/postgres/blob/44ef8b226a40f86cf9df3f9299067db6779a3aa3/16/bookworm/docker-entrypoint.sh#L331C4-L331C19
# https://github.com/docker-library/postgres/blob/44ef8b226a40f86cf9df3f9299067db6779a3aa3/16/bookworm/Dockerfile#L191
RUN sed -i 's/docker_setup_db$/docker_setup_db; \. \/schemamap\/init_schemamap.sh/g' /usr/local/bin/docker-entrypoint.sh
