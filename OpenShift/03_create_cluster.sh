#!/bin/bash
set -xe

source ../common/logging.sh
source common.sh

export OPENSHIFT_RELEASE_IMAGE="${OPENSHIFT_RELEASE_IMAGE:-registry.svc.ci.openshift.org/ocp/release:4.2}"
LOGLEVEL="${LOGLEVEL:-info}"

# Do not use unpigz to extract images due to race condition in vendored
# docker code that oc uses.
# See: https://github.com/openshift/oc/issues/58,
#      https://github.com/moby/moby/issues/39859
export MOBY_DISABLE_PIGZ=true

function extract_command() {
    local release_image
    local cmd
    local outdir
    local extract_dir

    cmd="$1"
    release_image="$2"
    outdir="$3"

    extract_dir=$(mktemp -d "installer--XXXXXXXXXX")
    pullsecret_file=$(mktemp "pullsecret--XXXXXXXXXX")

    echo "${PULL_SECRET}" > "${pullsecret_file}"
    oc adm release extract --registry-config "${pullsecret_file}" --command=$cmd --to "${extract_dir}" ${release_image}

    mv "${extract_dir}/${cmd}" "${outdir}"
    rm -rf "${extract_dir}"
    rm -rf "${pullsecret_file}"
}

# Let's always grab the `oc` from the release we're using.
function extract_oc() {
    extract_dir=$(mktemp -d "installer--XXXXXXXXXX")
    extract_command oc "$1" "${extract_dir}"
    sudo mv "${extract_dir}/oc" /usr/local/bin
    rm -rf "${extract_dir}"
}

function extract_installer() {
    local release_image
    local outdir

    release_image="$1"
    outdir="$2"

    extract_command openshift-baremetal-install "$1" "$2"
    export OPENSHIFT_INSTALLER="${outdir}/openshift-baremetal-install"
}

# TODO - Provide scripting to help generate install-config.yaml.
#  - https://github.com/openshift-kni/install-scripts/issues/19
if [ ! -f install-config.yaml ] ; then
    echo "Please create install-config.yaml"
    exit 1
fi

# Do some PULL_SECRET sanity checking
if [[ "${OPENSHIFT_RELEASE_IMAGE}" == *"registry.svc.ci.openshift.org"* ]]; then
    if [[ "${PULL_SECRET}" != *"registry.svc.ci.openshift.org"* ]]; then
        echo "Please get a valid pull secret for registry.svc.ci.openshift.org."
        exit 1
    fi
fi
if [[ "${PULL_SECRET}" != *"cloud.openshift.com"* ]]; then
    echo "Please get a valid pull secret for cloud.openshift.com."
    exit 1
fi

mkdir -p ocp
extract_oc ${OPENSHIFT_RELEASE_IMAGE}
extract_installer "${OPENSHIFT_RELEASE_IMAGE}" ocp/
cp install-config.yaml ocp/
${OPENSHIFT_INSTALLER} --dir ocp --log-level=${LOGLEVEL} create manifests
# TODO - Add custom install time manifests here:
#  - https://github.com/openshift-kni/install-scripts/issues/30
${OPENSHIFT_INSTALLER} --dir ocp --log-level=${LOGLEVEL} create cluster
