FROM rust:bookworm as builder
RUN apt update && apt install -y libssl-dev
WORKDIR /home/rust/src
COPY . .
# ARG FEATURES
RUN cd rust && cargo build --locked --release

FROM postgres:17.0
MAINTAINER Krisztian Szabo <krisz@schemamap.io>

COPY --from=builder /home/rust/src/rust/target/release/schemamap /usr/local/bin/schemamap

COPY ./docker/init_schemamap.sh /schemamap/init_schemamap.sh
RUN chmod +x /schemamap/init_schemamap.sh

# https://github.com/docker-library/postgres/blob/44ef8b226a40f86cf9df3f9299067db6779a3aa3/16/bookworm/docker-entrypoint.sh#L331C4-L331C19
# https://github.com/docker-library/postgres/blob/44ef8b226a40f86cf9df3f9299067db6779a3aa3/16/bookworm/Dockerfile#L191
RUN sed -i 's/docker_setup_db$/docker_setup_db; \/schemamap\/init_schemamap.sh/g' /usr/local/bin/docker-entrypoint.sh

# Postgres TCP forwarding
COPY ./docker/port-fwd-postgres.sh /usr/local/bin/port-fwd-postgres
