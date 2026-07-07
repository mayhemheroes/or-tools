# syntax=docker/dockerfile:1.7
FROM ghcr.io/mayhemheroes/base:20260621

ARG COMMIT
ARG REPO_URL
ARG SOURCE_DATE_EPOCH
ARG SANITIZER_FLAGS
ARG COVERAGE_FLAGS=
ARG MAYHEM_JOBS=

USER root
RUN [ -n "$SOURCE_DATE_EPOCH" ] && repro-sources-list.sh || true ; \
    apt-get update && apt-get install -yq --no-install-recommends \
      default-jdk-headless \
      libglpk-dev \
      python3 \
      wget \
    && wget -qO /usr/local/bin/bazel \
      https://github.com/bazelbuild/bazel/releases/download/8.0.1/bazel-8.0.1-linux-x86_64 \
    && chmod +x /usr/local/bin/bazel \
    && rm -rf /var/lib/apt/lists/*
USER mayhem
WORKDIR /mayhem
# Keep HOME on /mayhem so offline build.sh re-runs (verify-repo) have disk for Bazel.
# Mayhem cloud scratch goes to /dev/shm via TMPDIR + Mayhemfile env.
ENV HOME=/mayhem \
    TMPDIR=/dev/shm
COPY --chown=2000:2000 . /mayhem

RUN bash mayhem/build.sh
RUN bash mayhem/test.sh

LABEL org.opencontainers.image.source="${REPO_URL}" \
      org.opencontainers.image.revision="${COMMIT}" \
      rlenv.tier="commit" \
      rlenv.source_date_epoch="${SOURCE_DATE_EPOCH}" \
      rlenv.user="mayhem"

USER mayhem
WORKDIR /dev/shm
