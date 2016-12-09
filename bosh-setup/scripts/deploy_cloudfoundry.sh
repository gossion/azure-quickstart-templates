#!/usr/bin/env bash

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
SINGLE_MANIFEST="${SCRIPT_DIR}/example_manifests/single-vm-cf.yml"
CF_MANIFEST="${SCRIPT_DIR}/example_manifests/cf-deployment.yml"
DIEGO_MANIFEST="${SCRIPT_DIR}/example_manifests/diego-deployment.yml"

scenario=$1

source ${SCRIPT_DIR}/utils.sh

usage() {
  echo "Usage: ./deploy_cloudfoundry.sh <single|multiple>"
  exit 1
}


if [[ ${scenario} -ne "single" || ${scenario} -n "multiple" ]]; then
  usage
fi


# 1. For deploying all jobs in one single node, cf-release version will not be updated, it will use v238 for a long time.
#    Other releases for diego, garden, and so on will keep a workable version accordingly.
# 2. For deploying jobs in multiple nodes, we will try our best to keep the releases up-to-date.
#
if [[ $scenario == "single" ]]
then
  retryop "bosh upload stemcell REPLACE_WITH_STATIC_STEMCELL_URL --sha1 REPLACE_WITH_STATIC_STEMCELL_SHA1 --skip-if-exists"
  retryop "bosh upload release REPLACE_WITH_STATIC_CF_RELEASE_URL --sha1 REPLACE_WITH_STATIC_CF_RELEASE_SHA1 --skip-if-exists"
  retryop "bosh upload release REPLACE_WITH_STATIC_DIEGO_RELEASE_URL --sha1 REPLACE_WITH_STATIC_DIEGO_RELEASE_SHA1 --skip-if-exists"
  retryop "bosh upload release REPLACE_WITH_STATIC_GARDEN_RELEASE_URL --sha1 REPLACE_WITH_STATIC_GARDEN_RELEASE_SHA1 --skip-if-exists"
  retryop "bosh upload release REPLACE_WITH_STATIC_CFLINUXFS2_RELEASE_URL --sha1 REPLACE_WITH_STATIC_CFLINUXFS2_RELEASE_SHA1 --skip-if-exists"
  bosh deployment ${SINGLE_MANIFEST}
  bosh -n deploy
elif [[ $scenario == "multiple" ]]
  retryop "bosh upload stemcell REPLACE_WITH_DYNAMIC_STEMCELL_URL --sha1 REPLACE_WITH_DYNAMIC_STEMCELL_SHA1 --skip-if-exists"
  retryop "bosh upload release REPLACE_WITH_DYNAMIC_CF_RELEASE_URL --sha1 REPLACE_WITH_DYNAMIC_CF_RELEASE_SHA1 --skip-if-exists"
  retryop "bosh upload release REPLACE_WITH_DYNAMIC_DIEGO_RELEASE_URL --sha1 REPLACE_WITH_DYNAMIC_DIEGO_RELEASE_SHA1 --skip-if-exists"
  retryop "bosh upload release REPLACE_WITH_DYNAMIC_GARDEN_RELEASE_URL --sha1 REPLACE_WITH_DYNAMIC_GARDEN_RELEASE_SHA1 --skip-if-exists"
  retryop "bosh upload release REPLACE_WITH_DYNAMIC_CFLINUXFS2_RELEASE_URL --sha1 REPLACE_WITH_DYNAMIC_CFLINUXFS2_RELEASE_SHA1 --skip-if-exists"
  bosh deployment ${CF_MANIFEST}
  bosh -n deploy
  bosh deployment ${DIEGO_MANIFEST}
  bosh -n deploy
else
  usage
fi
