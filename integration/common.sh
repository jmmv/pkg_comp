#! __ATF_SH__
# Copyright 2017 Google Inc.
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are
# met:
#
# * Redistributions of source code must retain the above copyright
#   notice, this list of conditions and the following disclaimer.
# * Redistributions in binary form must reproduce the above copyright
#   notice, this list of conditions and the following disclaimer in the
#   documentation and/or other materials provided with the distribution.
# * Neither the name of Google Inc. nor the names of its contributors
#   may be used to endorse or promote products derived from this software
#   without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
# "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
# LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
# A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
# OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
# SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
# LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
# DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
# THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
# (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
# OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

# \file common.sh
# Common code for all integration tests.


# Paths to installed files.
#
# Can be overriden for test purposes only.
: ${PKG_COMP_ETCDIR="__PKG_COMP_ETCDIR__"}
: ${PKG_COMP_SHAREDIR="__PKG_COMP_SHAREDIR__"}


integration_test_case() {
    shtk_unittest_add_test "${1}" cleanup
    eval "${1}_body() { integration_body; ${1}_intbody; }"
    eval "${1}_cleanup() { integration_cleanup; }"
}
integration_body() {
    cat >pkg_comp.conf <<EOF
DISTDIR="${TEST_ENV_distdir}"
PACKAGES="$(pwd)/packages/pkg"
PBULK_PACKAGES="$(pwd)/packages/pbulk"
PKGSRCDIR="${TEST_ENV_pkgsrcdir}"
SANDBOX_CONFFILE="$(pwd)/sandbox.conf"

LOCALBASE=/test/prefix
PKG_DBDIR=/test/pkgdb
SYSCONFDIR=/test/etc
VARBASE=/test/var
EOF

    cp "${TEST_ENV_sandbox_conffile}" sandbox.conf
    cat >>sandbox.conf <<EOF
SANDBOX_ROOT="$(pwd)/sandbox"
EOF

    mkdir packages
}
integration_cleanup() {
    if [ -d sandbox ]; then
        pkg_comp -c pkg_comp.conf sandbox-unmount -f -f || true
        pkg_comp -c pkg_comp.conf sandbox-destroy || true
    fi
}


# Configures the test to use Git to pull from pkgsrcgit.
setup_fetch_from_local_git() {
    [ -d "${TEST_ENV_pkgsrcdir}" ] || atf_skip "pkgsrcdir does not" \
        "point to a Git repository"

    echo "PKGSRCDIR='$(pwd)/pkgsrc'" >>pkg_comp.conf
    # Prefer git for a faster test.
    if which git >/dev/null 2>&1; then
        echo "FETCH_VCS=git" >>pkg_comp.conf
        echo "GIT_URL='file://${TEST_ENV_pkgsrcdir}'" >>pkg_comp.conf
    fi
}


# Asks the test to reuse existing binary packages, if allowed by the user.
#
# The binary packages are taken from the PACKAGES directory configured by the
# user if they exist, and they must have been built by this test suite.  Note
# that reusing binaries can lead to flakiness... but sometimes speedier tests
# are desired.
#
# \param ... Basenames of the packages to reuse, if they exist.
reuse_packages() {
    if atf_config_has packages; then
        echo "The 'packages' configuration variable is set."
        echo "Reusing any pre-existing binary packages for: ${*}"
        echo "Note: cp errors are normal here."

        mkdir -p packages/pkg/All
        for pkgbase in "${@}"; do
            cp "${TEST_ENV_packages}/pkg/All/${pkgbase}"-[0-9]*.tgz \
               packages/pkg/All || true
        done
    fi
}


# Asks the test to reuse existing bootstrap binaries, if allowed by the user.
#
# The bootstrap kits and packages are taken from the PACKAGES directory
# configured by the user if they exist, and they must have been built by this
# test suite.  Note that reusing binaries can lead to flakiness... but speedier
# tests are preferrable during development.
reuse_bootstrap() {
    if atf_config_has packages; then
        local packages="${TEST_ENV_packages}"

        echo "The 'packages' configuration variable is set."
        echo "Reusing any pre-existing bootstrap binary kits and packages."
        echo "Note: cp errors are normal here."

        mkdir -p packages/pkg
        cp "${packages}/pkg/bootstrap.tgz" packages/pkg || true
        cp -rf "${packages}/pbulk" packages || true

        # Reuse the list of packages built for pbulk as the "bootstrap" packages
        # to copy from the pkg tree.  This is an overapproximation though: the
        # pbulk packages contain more than just the bootstrap packages, but the
        # extra ones should not exist for our test scenarios.
        local pbulk_packages="$(cd "${packages}/pbulk/All" \
            && ls -1 *.tgz | sed -e 's,-[0-9].*$,,')"
        reuse_packages ${pbulk_packages}
    fi
}


# Persists bootstrap kits and built packages for future test reuse.
#
# If the user has allowed the reuse of built results across test invocations by
# setting the 'packages' variable, copy all artifacts into PACKAGES so that
# reuse_packages and reuse_bootstrap can use them later.
save_state() {
    if atf_config_has packages; then
        local packages="${TEST_ENV_packages}"
        mkdir -p "${packages}/pbulk/All"
        cp packages/pbulk/bootstrap.tgz "${packages}/pbulk" || true
        cp packages/pbulk/All/* "${packages}/pbulk/All" || true
        mkdir -p "${packages}/pkg/All"
        cp packages/pkg/bootstrap.tgz "${packages}/pkg" || true
        cp packages/pkg/All/* "${packages}/pkg/All" || true
    fi
}


# Ensures that the given list of files exist.
check_files() {
    for file in "${@}"; do
        [ -e "${file}" ] || atf_fail "Expected file ${file} not found"
    done
}


# Ensures that the given list of files do not exist.
check_not_files() {
    for file in "${@}"; do
        [ ! -e "${file}" ] || atf_fail "Unexpected file ${file} found"
    done
}


# Ensures that a given package name appears in the pkg_summary files.
#
# \param dir Path to the directory containing the pkg_summary files.
# \param pkgname Basename of the package to search for.
check_pkg_summary() {
    local dir="${1}"; shift
    local pkgname="${1}"; shift

    gunzip -c "${dir}/pkg_summary.gz" | grep "PKGNAME=${pkgname}-[0-9]" \
        || atf_fail "pkg_summary.gz does not contain ${pkgname}"
    bunzip2 -c "${dir}/pkg_summary.bz2" | grep "PKGNAME=${pkgname}-[0-9]" \
        || atf_fail "pkg_summary.bz2 does not contain ${pkgname}"
}
