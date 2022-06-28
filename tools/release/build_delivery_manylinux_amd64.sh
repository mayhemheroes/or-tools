#!/usr/bin/env bash
# Copyright 2010-2022 Google LLC
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -eo pipefail

function help() {
  local -r NAME=$(basename "$0")
  local -r BOLD="\e[1m"
  local -r RESET="\e[0m"
  local -r help=$(cat << EOF
${BOLD}NAME${RESET}
\t$NAME - Build delivery using an ${BOLD}Centos 7 docker image${RESET}.
${BOLD}SYNOPSIS${RESET}
\t$NAME [-h|--help|help] [examples|dotnet|java|python|all|reset]
${BOLD}DESCRIPTION${RESET}
\tBuild Google OR-Tools deliveries.
\tYou ${BOLD}MUST${RESET} define the following variables before running this script:
\t* ORTOOLS_TOKEN: secret use to decrypt keys to sign .Net and Java packages.

${BOLD}OPTIONS${RESET}
\t-h --help: display this help text
\tdotnet: build all .Net packages
\tjava: build all Java packages
\tpython: build all Pyhon packages
\texamples: build examples archives
\tall: build everything (default)

${BOLD}EXAMPLES${RESET}
Using export to define the ${BOLD}ORTOOLS_TOKEN${RESET} env and only building the Java packages:
export ORTOOLS_TOKEN=SECRET
$0 java

note: the 'export ...' should be placed in your bashrc to avoid any leak
of the secret in your bash history
EOF
)
echo -e "$help"
}

function assert_defined(){
  if [[ -z "${!1}" ]]; then
    >&2 echo "Variable '${1}' must be defined"
    exit 1
  fi
}

function build_delivery() {
  assert_defined ORTOOLS_BRANCH
  assert_defined ORTOOLS_SHA1
  assert_defined ORTOOLS_TOKEN
  assert_defined ORTOOLS_DELIVERY
  assert_defined DOCKERFILE
  assert_defined ORTOOLS_IMG

  # Clean
  docker image rm -f "${ORTOOLS_IMG}":"${ORTOOLS_DELIVERY}" 2>/dev/null
  docker image rm -f "${ORTOOLS_IMG}":devel 2>/dev/null
  docker image rm -f "${ORTOOLS_IMG}":env 2>/dev/null

  cd "${RELEASE_DIR}" || exit 2

  # Build env
  docker build --tag "${ORTOOLS_IMG}":env \
    --build-arg ORTOOLS_GIT_BRANCH="${ORTOOLS_BRANCH}" \
    --build-arg ORTOOLS_GIT_SHA1="${ORTOOLS_SHA1}" \
    --target=env \
    -f ${DOCKERFILE} .

  # Build devel
  docker build --tag "${ORTOOLS_IMG}":devel \
    --build-arg ORTOOLS_GIT_BRANCH="${ORTOOLS_BRANCH}" \
    --build-arg ORTOOLS_GIT_SHA1="${ORTOOLS_SHA1}" \
    --target=devel \
    -f ${DOCKERFILE} .

  # Build delivery
  docker build --tag "${ORTOOLS_IMG}":"${ORTOOLS_DELIVERY}" \
    --build-arg ORTOOLS_GIT_BRANCH="${ORTOOLS_BRANCH}" \
    --build-arg ORTOOLS_GIT_SHA1="${ORTOOLS_SHA1}" \
    --build-arg ORTOOLS_TOKEN="${ORTOOLS_TOKEN}" \
    --build-arg ORTOOLS_DELIVERY="${ORTOOLS_DELIVERY}" \
    --target=delivery \
    -f ${DOCKERFILE} .
}

# .Net build
function build_dotnet() {
  assert_defined ORTOOLS_IMG
  local -r ORTOOLS_DELIVERY=dotnet
  build_delivery

  docker run --rm --init \
  -w /root/or-tools \
  -v "${ROOT_DIR}/export":/export \
  -u $(id -u ${USER}):$(id -g ${USER}) \
  -t "${ORTOOLS_IMG}":"${ORTOOLS_DELIVERY}" "cp export/*nupkg /export/"
}

# Java build
function build_java() {
  assert_defined ORTOOLS_IMG
  local -r ORTOOLS_DELIVERY=java
  build_delivery

  docker run --rm --init \
  -w /root/or-tools \
  -v "${ROOT_DIR}/export":/export \
  -u $(id -u ${USER}):$(id -g ${USER}) \
  -t "${ORTOOLS_IMG}":"${ORTOOLS_DELIVERY}" "cp export/*.jar* /export/"
}

# Python build
function build_python() {
  local -r ORTOOLS_DELIVERY=python
  build_delivery
}

function build_archive() {
  local -r ORTOOLS_DELIVERY=archive
  build_delivery
}

function build_examples() {
  local -r ORTOOLS_DELIVERY=examples
  build_delivery
}

# Main
function main() {
  case ${1} in
    -h | --help | help)
      help; exit ;;
  esac

  assert_defined ORTOOLS_TOKEN
  echo "ORTOOLS_TOKEN: FOUND"

  local -r ROOT_DIR="$(cd -P -- "$(dirname -- "$0")/../.." && pwd -P)"
  echo "ROOT_DIR: '${ROOT_DIR}'"

  local -r RELEASE_DIR="$(cd -P -- "$(dirname -- "$0")" && pwd -P)"
  echo "RELEASE_DIR: '${RELEASE_DIR}'"

  local -r ORTOOLS_BRANCH=$(git rev-parse --abbrev-ref HEAD)
  local -r ORTOOLS_SHA1=$(git rev-parse --verify HEAD)
  local -r DOCKERFILE=amd64.Dockerfile
  local -r ORTOOLS_IMG="ortools/manylinux_delivery_amd64"

  mkdir -p export
  case ${1} in
    dotnet|java|python|archive|examples)
      "build_$1"
      exit ;;
    all)
      build_dotnet
      build_java
      #build_python
      build_examples
      exit ;;
    *)
      >&2 echo "Target '${1}' unknown"
      exit 1
  esac
  exit 0
}

main "${1:-all}"
