default:
  @just --list

build:
  docker build . \
    -t schemamap/postgres:latest \
    -t schemamap/postgres:17.0 \
    -t schemamap/postgres:17.0-v0.4.2

# One-time setup of BuildKit so multi-arch builds are possible
buildx-setup:
  docker buildx create --name mybuilder --use
  docker buildx install

# Builds all common architectures that are supported by the official Postgres image
buildx-and-push:
  docker build --platform linux/amd64,linux/arm64,linux/arm/v7 . \
    -t schemamap/postgres:latest \
    -t schemamap/postgres:17.0 \
    -t schemamap/postgres:17.0-v0.4.2 \
    --push

login:
  docker login -u schemamap

push:
  docker push schemamap/postgres:17.0
  docker push schemamap/postgres:latest

up:
  docker-compose up --build

psql:
  PGPASSWORD=postgres psql -h 127.0.0.1 -p 5433 -U postgres postgres

clean:
  docker-compose rm -f
