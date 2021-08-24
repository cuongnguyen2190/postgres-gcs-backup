# FROM python:3.9.6-alpine3.14
FROM alpine:3.14

RUN apk add --update \
  bash \
  postgresql \
  curl \
  # python \
  py-pip \
  py-cffi \
  && pip install --upgrade pip \
  && apk add --virtual build-deps \
  gcc \
  libffi-dev \
  python3-dev \
  linux-headers \
  musl-dev \
  openssl-dev \
  cargo \
  && apk del build-deps \
  && rm -rf /var/cache/apk/*

RUN curl -sSL https://sdk.cloud.google.com | bash

ENV PATH $PATH:/root/google-cloud-sdk/bin

ADD . /postgres-gcs-backup

WORKDIR /postgres-gcs-backup

RUN chmod +x /postgres-gcs-backup/backup.sh

ENTRYPOINT ["/postgres-gcs-backup/backup.sh"]
