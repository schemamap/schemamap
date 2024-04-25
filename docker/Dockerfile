FROM alpine:3.19 as rathole-downloader

# Add rathole static binary to path
RUN file=$(case "$(uname -m)" in \
      "aarch64") echo "rathole-aarch64-unknown-linux-musl.zip";; \
      "x86_64") echo "rathole-x86_64-unknown-linux-gnu.zip";; \
      "armv7l") echo "rathole-armv7-unknown-linux-musleabihf.zip";; \
      "arm") echo "rathole-arm-unknown-linux-musleabihf.zip";; *);; esac) \
    && wget -O rathole.zip "https://github.com/rapiz1/rathole/releases/download/v0.5.0/${file}" \
    && unzip rathole.zip

FROM postgres:16.2
MAINTAINER Krisztian Szabo <krisz@schemamap.io>

# Postgres Migrations
COPY ./init_schemamap.sh /schemamap/init_schemamap.sh
COPY ./*.sql /schemamap/

# https://github.com/docker-library/postgres/blob/44ef8b226a40f86cf9df3f9299067db6779a3aa3/16/bookworm/docker-entrypoint.sh#L331C4-L331C19
# https://github.com/docker-library/postgres/blob/44ef8b226a40f86cf9df3f9299067db6779a3aa3/16/bookworm/Dockerfile#L191
RUN sed -i 's/docker_setup_db$/docker_setup_db; \. \/schemamap\/init_schemamap.sh/g' /usr/local/bin/docker-entrypoint.sh

# Postgres TCP forwarding
COPY --from=rathole-downloader /rathole /usr/local/bin/rathole
COPY ./port-fwd-postgres.sh /usr/local/bin/port-fwd-postgres
