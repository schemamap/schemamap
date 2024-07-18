default:
  @just --list

build:
  docker build . \
    -t schemamap/postgres:latest \
    -t schemamap/postgres:16.2 \
    -t schemamap/postgres:16.2-v0.3.0

# One-time setup of BuildKit so multi-arch builds are possible
buildx-setup:
  docker buildx create --name mybuilder --use
  docker buildx install

# Builds all common architectures that are supported by the official Postgres image
buildx-and-push:
  docker build --platform linux/amd64,linux/arm64,linux/arm/v7 . \
    -t schemamap/postgres:latest \
    -t schemamap/postgres:16.2 \
    -t schemamap/postgres:16.2-v0.3.0 \
    --push

login:
  docker login -u schemamap

push:
  docker push schemamap/postgres:16.2
  docker push schemamap/postgres:latest

up:
  docker-compose up --build

psql:
  PGPASSWORD=postgres psql -h 127.0.0.1 -p 5433 -U postgres postgres

clean:
  docker-compose rm -f
