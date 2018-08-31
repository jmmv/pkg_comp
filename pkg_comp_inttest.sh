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

# \file pkg_comp_inttest.sh
# Integration tests for the pkg_comp.sh script.
#
# The tests in this script are expensive to run: they use a real pkgsrc tree and
# a real sandbox, and test the various integration points of pkg_comp with the
# pkgsrc infrastructure (i.e. they build software).  These are "the real tests"
# because they ensure that pkgsrc works within the context of the sandbox we
# have created, and that pkg_comp is executing commands correctly; however, this
# also means that these can be fragile, as they are subject to pkgsrc API
# changes (good for us to spot problems) and breakage (bad as these are not our
# fault).
#
# The following configuration variables must be set:
#
#     test_suites.pkg_comp.distdir
#         Path to the persistent cache for distribution files.  This is safe to
#         reuse across test invocations.  Read-write.
#
#     test_suites.pkg_comp.packages
#         Path to a directory to hold built packages.  If not set, tests will
#         always start from a pristine state so they will be more robust.  If
#         set, tests may become flaky over time so set only if you know what you
#         are doing.  Read-write.
#
#     test_suites.pkg_comp.pkgsrcdir
#         Path to an pkgsrc tree cloned from Git.  Read-only.
#
#     test_suites.pkg_comp.sandbox_conffile
#         Path to a sandboxctl(8) configuration file to create a clean sandbox
#         for the current operating system.


# Controls sharding for the long-running integration tests in this file.
#
# Travis CI imposes a 1-hour limit for the execution of each individual build,
# which is insufficient to run all of our integration tests.  To make testing
# possible, we support sharding execution.  The INTTEST_SHARD variable
# indicates the identifier of this shard, which has to be in the range from
# zero to INTTEST_SHARDS.
#
# TODO(jmmv): This feature should be supported natively by Kyua.
: ${INTTEST_SHARD=0}
: ${INTTEST_SHARDS=1}


# Paths to installed files.
#
# Can be overriden for test purposes only.
: ${PKG_COMP_ETCDIR="__PKG_COMP_ETCDIR__"}
: ${PKG_COMP_SHAREDIR="__PKG_COMP_SHAREDIR__"}


integration_test_case() {
    atf_test_case "${1}" cleanup
    eval "${1}_inthead() { true; }"
    eval "${1}_head() { integration_head; ${1}_inthead; }"
    eval "${1}_body() { integration_body; ${1}_intbody; }"
    eval "${1}_cleanup() { integration_cleanup; }"
}
integration_head() {
    atf_set require.config "distdir pkgsrcdir sandbox_conffile"
    atf_set require.user "root"
    atf_set timeout 3600
}
integration_body() {
    cat >pkg_comp.conf <<EOF
DISTDIR="$(atf_config_get distdir)"
PACKAGES="$(pwd)/packages/pkg"
PBULK_LOG="$(pwd)/bulklog"
PBULK_PACKAGES="$(pwd)/packages/pbulk"
PKGSRCDIR="$(atf_config_get pkgsrcdir)"
SANDBOX_CONFFILE="$(pwd)/sandbox.conf"

LOCALBASE=/test/prefix
PKG_DBDIR=/test/pkgdb
SYSCONFDIR=/test/etc
VARBASE=/test/var
EOF

    cp "$(atf_config_get sandbox_conffile)" sandbox.conf
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
    [ -d "$(atf_config_get pkgsrcdir)" ] || atf_skip "pkgsrcdir does not" \
        "point to a Git repository"

    echo "PKGSRCDIR='$(pwd)/pkgsrc'" >>pkg_comp.conf
    # Prefer git for a faster test.
    if which git >/dev/null 2>&1; then
        echo "FETCH_VCS=git" >>pkg_comp.conf
        echo "GIT_URL='file://$(atf_config_get pkgsrcdir)'" >>pkg_comp.conf
    fi

    # Configure Git in case our tests want to modify the pkgsrc files.  In those
    # cases, pkg_comp will need to stash the modifications during "fetch" and
    # we need these details.
    git config --global user.email "travis@example.com"
    git config --global user.name "Travis"
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
            cp "$(atf_config_get packages)/pkg/All/${pkgbase}"-[0-9]*.tgz \
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
        local packages="$(atf_config_get packages)"

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
        local packages="$(atf_config_get packages)"
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


integration_test_case bootstrap_workflow
bootstrap_workflow_intbody() {
    atf_check -e ignore pkg_comp -c pkg_comp.conf sandbox-create

    # Bootstrap with an empty PACKAGES directory, which requires a rebuild from
    # sources and results in binaries for reinstallation.

    atf_check \
        -o match:'=> No binary package found for .*pbulk' \
        -e match:'^pkg_comp: .*Bootstrapping pkg tools' \
        -e match:'^pkg_comp: .*Bootstrapping pbulk tools' \
        -e not-match:'^pkg_comp: .*Setting up .*using binary kit' \
        pkg_comp -c pkg_comp.conf bootstrap

    # Now check that the contents of the sandbox are sane and store the list of
    # files for later comparison with rebuilt sandboxes.

    check_files \
        packages/pbulk/All/bmake-[0-9]* \
        packages/pbulk/All/pbulk-[0-9]* \
        packages/pbulk/All/pkg_install-[0-9]* \
        packages/pbulk/bootstrap.tgz \
        packages/pkg/All/bmake-[0-9]* \
        packages/pkg/All/pkg_install-[0-9]* \
        packages/pkg/bootstrap.tgz \
        sandbox/test/etc/mk.conf \
        sandbox/test/pkgdb/pkgdb.byfile.db \
        sandbox/test/prefix/bin/bmake
    rm -rf sandbox/pkg_comp/work sandbox/tmp/* sandbox/var/tmp/*
    find sandbox | sort >exp_contents.txt

    # Bootstrap without destroying the sandbox, which should not do anything.

    atf_check pkg_comp -c pkg_comp.conf bootstrap
    rm -rf sandbox/pkg_comp/work sandbox/tmp/* sandbox/var/tmp/*
    atf_check -o file:exp_contents.txt -x "find sandbox | sort"

    # Bootstrap after destroying the sandbox but keeping PACKAGES, which should
    # result in no rebuilds.

    atf_check -e ignore pkg_comp -c pkg_comp.conf sandbox-destroy
    atf_check -e ignore pkg_comp -c pkg_comp.conf sandbox-create

    atf_check \
        -o not-match:'=> No binary package found for .*pbulk' \
        -o not-match:'=> Building for .*pbulk' \
        -e match:'^pkg_comp: .*Bootstrapping pkg tools' \
        -e match:'^pkg_comp: .*Bootstrapping pbulk tools' \
        -e match:'^pkg_comp: .*Setting up .*/test/prefix using binary kit' \
        -e match:'^pkg_comp: .*Setting up .*/pkg_comp/pbulk using binary kit' \
        pkg_comp -c pkg_comp.conf bootstrap
    rm -rf sandbox/pkg_comp/work sandbox/tmp/* sandbox/var/tmp/*
    # When we build pbulk before, pkgsrc might have installed helper build
    # tools.  We are now using binary packages, so those build tools will not be
    # present.  Special-case them here, though this is quite fragile.
    grep -v nbpatch exp_contents.txt >exp_contents.clean.txt
    atf_check -o file:exp_contents.clean.txt -x "find sandbox | sort"

    # Ensure the public bootstrap kit does not leak pkg_comp settings.
    tar xzvf packages/pkg/bootstrap.tgz ./test/etc/mk.conf
    if grep /pkg_comp/ ./test/etc/mk.conf; then
        atf_fail "Found internal paths to the sandbox in mk.conf"
    fi

    atf_check -e ignore pkg_comp -c pkg_comp.conf sandbox-destroy
    save_state
}


integration_test_case functional_pkgsrc_after_bootstrap
functional_pkgsrc_after_bootstrap_intbody() {
    reuse_bootstrap

    # Verify that the bootstrapped sandbox is sane and can build a simple
    # package.

    atf_check -e ignore pkg_comp -c pkg_comp.conf sandbox-create
    atf_check -o ignore -e ignore pkg_comp -c pkg_comp.conf bootstrap

    [ ! -e sandbox/test/prefix/bin/digest ] || atf_fail "digest was already" \
        "installed in the sandbox but it should not be there"
    rm -f packages/pkg/All/digest-[0-9]*
    atf_check \
        -o match:'=> Building for .*digest' \
        -e ignore \
        pkg_comp -c pkg_comp.conf sandbox-run \
        /bin/sh -c 'cd /pkg_comp/pkgsrc/pkgtools/digest \
            && /test/prefix/bin/bmake bin-install'
    check_files \
        packages/pkg/All/digest-[0-9]* \
        sandbox/test/prefix/bin/digest

    # Rebootstrap the sandbox and try to reinstall the same package, which
    # should result in a binary reuse.

    atf_check -e ignore pkg_comp -c pkg_comp.conf sandbox-destroy
    atf_check -e ignore pkg_comp -c pkg_comp.conf sandbox-create
    atf_check -o ignore -e ignore pkg_comp -c pkg_comp.conf bootstrap

    [ ! -e sandbox/test/prefix/bin/digest ] || atf_fail "digest was already" \
        "installed in the sandbox but it should not be there"
    atf_check \
        -o not-match:'=> Building for .*digest' \
        -e ignore \
        pkg_comp -c pkg_comp.conf sandbox-run \
        /bin/sh -c 'cd /pkg_comp/pkgsrc/pkgtools/digest \
            && /test/prefix/bin/bmake bin-install'
    check_files \
        packages/pkg/All/digest-[0-9]* \
        sandbox/test/prefix/bin/digest

    atf_check -e ignore pkg_comp -c pkg_comp.conf sandbox-destroy
    save_state
}


integration_test_case build_workflow
build_workflow_intbody() {
    reuse_bootstrap
    reuse_packages cwrappers digest pkgconf shtk sysbuild

    # Disable tests to make the build below a bit faster, and also to ensure
    # that the extra mk.conf fragment is picked up.
    echo "PKG_DEFAULT_OPTIONS=-tests" >extra.mk.conf
    echo "EXTRA_MKCONF='$(pwd)/extra.mk.conf'" >>pkg_comp.conf

    # Verify that package name validation works.
    atf_check \
        -s exit:1 \
        -o not-match:'Starting build' \
        -e match:'W:.*foo.* does not exist' \
        -e not-match:'W:.*sysbuild.* does not exist' \
        -e match:'W:.*bar.* does not exist' \
        -e not-match:'W:.*[^/]tmux.* does not exist' \
        -e match:'W:.*misc/baz.* does not exist' \
        pkg_comp -c pkg_comp.conf build foo sysbuild bar misc/tmux misc/baz

    # Start by building an arbitrary package that is certainly not included in
    # the bootstrapping process.  The package we choose, sysbuild, has one
    # dependency and we need at least one for our testing purposes.
    atf_check -e ignore pkg_comp -c pkg_comp.conf sandbox-create
    atf_check \
        -o not-match:'Starting build of .*atf-[0-9]' \
        -o match:'Starting build of .*shtk-[0-9]' \
        -o match:'Successfully built .*shtk-[0-9]' \
        -o match:'Starting build of .*sysbuild-[0-9]' \
        -o match:'Successfully built .*sysbuild-[0-9]' \
        -e ignore \
        pkg_comp -c pkg_comp.conf build sysbuild
    check_files packages/pkg/All/shtk-[0-9]*
    check_files packages/pkg/All/sysbuild-[0-9]*
    check_pkg_summary packages/pkg/All shtk
    check_pkg_summary packages/pkg/All sysbuild

    # pbulk installs only intermediate dependencies but does not install the
    # final package we asked, so install it now to ensure things work.
    atf_check -o ignore -e ignore \
        pkg_comp -c pkg_comp.conf sandbox-run \
        /bin/sh -c 'cd /pkg_comp/packages/pkg/All && \
            /test/prefix/sbin/pkg_add sysbuild'
    check_files sandbox/test/prefix/bin/sysbuild

    # Delete an intermediate package and ensure it gets rebuilt even if not
    # directly specified on the command line.
    rm packages/pkg/All/shtk-*
    check_not_files packages/pkg/All/shtk-[0-9]*
    atf_check -o ignore -e ignore pkg_comp -c pkg_comp.conf build sysbuild
    check_files packages/pkg/All/shtk-[0-9]*
    check_files packages/pkg/All/sysbuild-[0-9]*
    check_pkg_summary packages/pkg/All shtk
    check_pkg_summary packages/pkg/All sysbuild

    # Delete an intermediate package and ensure that building it alone does
    # not cause other binary packages to be discarded.
    rm packages/pkg/All/shtk-*
    check_not_files packages/pkg/All/shtk-[0-9]*
    atf_check \
        -o match:'Starting build of .*shtk-[0-9]' \
        -o match:'Successfully built .*shtk-[0-9]' \
        -o not-match:'Starting build of .*sysbuild-[0-9]' \
        -e ignore \
        pkg_comp -c pkg_comp.conf build shtk
    check_files packages/pkg/All/shtk-[0-9]*
    check_files packages/pkg/All/sysbuild-[0-9]*  # Has to be there!
    check_pkg_summary packages/pkg/All shtk
    check_pkg_summary packages/pkg/All sysbuild  # Has to be there!

    atf_check -e ignore pkg_comp -c pkg_comp.conf sandbox-destroy
    save_state
}


integration_test_case auto_workflow
auto_workflow_intbody() {
    reuse_bootstrap
    reuse_packages cwrappers digest pkgconf shtk sysbuild

    # Configure cvs to later verify that calls are properly invoked.
    mkdir bin
    cat >bin/cvs <<EOF
#! /bin/sh
touch $(pwd)/cvs.done
exit 0
EOF
    chmod +x bin/cvs
    export PATH="$(pwd)/bin:${PATH}"
    echo "CVS_ROOT=fake-cvsroot" >>pkg_comp.conf
    echo "CVS_TAG=fake-cvstag" >>pkg_comp.conf

    # Disable tests to make the build below a bit faster, and also to ensure
    # that the extra mk.conf fragment is picked up.
    echo "PKG_DEFAULT_OPTIONS=-tests" >extra.mk.conf
    echo "EXTRA_MKCONF='$(pwd)/extra.mk.conf'" >>pkg_comp.conf

    # Verify that we must have provided at least one package before doing
    # anything.
    atf_check -s exit:1 -e match:"requires.*one package name" \
        pkg_comp -c pkg_comp.conf auto
    check_not_files cvs.done sandbox

    # Verify that package name validation works and that it happens before
    # building anything.
    atf_check \
        -s exit:1 \
        -o not-match:'Starting build' \
        -e match:'W:.*foo.* does not exist' \
        -e not-match:'W:.*sysbuild.* does not exist' \
        -e match:'W:.*bar.* does not exist' \
        -e not-match:'W:.*[^/]tmux.* does not exist' \
        -e match:'W:.*misc/baz.* does not exist' \
        pkg_comp -c pkg_comp.conf auto foo sysbuild bar misc/tmux misc/baz
    check_files cvs.done
    rm cvs.done
    check_not_files sandbox

    # Start by building an arbitrary package that is certainly not included in
    # the bootstrapping process.  The package we choose, sysbuild, has one
    # dependency and we need at least one for our testing purposes.
    echo "AUTO_PACKAGES='sysbuild'" >>pkg_comp.conf
    atf_check \
        -o not-match:'Starting build of .*atf-[0-9]' \
        -o match:'Starting build of .*shtk-[0-9]' \
        -o match:'Successfully built .*shtk-[0-9]' \
        -o match:'Starting build of .*sysbuild-[0-9]' \
        -o match:'Successfully built .*sysbuild-[0-9]' \
        -e not-match:'pkg_comp: I: Updating pkgsrc tree' \
        -e match:'pkg_comp: I: Creating sandbox' \
        -e match:'pkg_comp: I: Destroying sandbox' \
        pkg_comp -c pkg_comp.conf auto -f
    check_files packages/pkg/All/shtk-[0-9]*
    check_files packages/pkg/All/sysbuild-[0-9]*
    check_not_files cvs.done sandbox
    check_pkg_summary packages/pkg/All shtk
    check_pkg_summary packages/pkg/All sysbuild

    # Now pass the packages to build on the command line.  As the sandbox has
    # been recreated, we should not see the packages we asked earlier being
    # built, but they should remain.
    atf_check \
        -o not-match:'Starting build of .*atf-[0-9]' \
        -o match:'Starting build of .*shtk-[0-9]' \
        -o match:'Successfully built .*shtk-[0-9]' \
        -o not-match:'Starting build of .*sysbuild-[0-9]' \
        -o not-match:'Successfully built .*sysbuild-[0-9]' \
        -e not-match:'pkg_comp: I: Updating pkgsrc tree' \
        -e match:'pkg_comp: I: Creating sandbox' \
        -e match:'pkg_comp: I: Destroying sandbox' \
        pkg_comp -c pkg_comp.conf auto -f shtk
    check_files packages/pkg/All/shtk-[0-9]*
    check_files packages/pkg/All/sysbuild-[0-9]*  # Has to be there!
    check_pkg_summary packages/pkg/All shtk
    check_pkg_summary packages/pkg/All sysbuild  # Has to be there!
    check_not_files cvs.done sandbox

    # Check cvs operations in non-fast mode.
    atf_check \
        -o match:'Starting build of .*shtk-[0-9]' \
        -o match:'Successfully built .*shtk-[0-9]' \
        -e match:"Running.*cvs.*in $(atf_config_get pkgsrcdir)" \
        -e match:'cvs.*-dfake-cvsroot.*update.*-d.*-P.*-rfake-cvstag' \
        -e match:'pkg_comp: I: Updating pkgsrc tree' \
        -e match:'pkg_comp: I: Creating sandbox' \
        -e match:'pkg_comp: I: Destroying sandbox' \
        pkg_comp -c pkg_comp.conf auto shtk
    check_files cvs.done

    save_state
}


integration_test_case fetch_workflow
fetch_workflow_inthead() {
    atf_set require.progs "git"
}
fetch_workflow_intbody() {
    setup_fetch_from_local_git

    check_not_files pkgsrc/mk/bsd.pkg.mk
    atf_check \
        -o ignore \
        -e match:'pkg_comp: I: Updating pkgsrc tree' \
        pkg_comp -c pkg_comp.conf fetch
    check_files pkgsrc/mk/bsd.pkg.mk
}


integration_test_case auto_workflow_with_fetch
auto_workflow_with_fetch_inthead() {
    atf_set require.progs "git"
}
auto_workflow_with_fetch_intbody() {
    reuse_bootstrap
    reuse_packages cwrappers digest pkgconf shtk sysbuild

    setup_fetch_from_local_git

    # Disable tests to make the build below a bit faster, and also to ensure
    # that the extra mk.conf fragment is picked up.
    echo "PKG_DEFAULT_OPTIONS=-tests" >extra.mk.conf
    echo "EXTRA_MKCONF='$(pwd)/extra.mk.conf'" >>pkg_comp.conf

    # Build one package, which will need to fetch the pkgsrc tree.
    atf_check \
        -o not-match:'Starting build of .*atf-[0-9]' \
        -o match:'Starting build of .*shtk-[0-9]' \
        -o match:'Successfully built .*shtk-[0-9]' \
        -e match:'pkg_comp: I: Updating pkgsrc tree' \
        pkg_comp -c pkg_comp.conf auto shtk
    check_files pkgsrc/mk/bsd.pkg.mk
    check_files packages/pkg/All/shtk-[0-9]*
    check_pkg_summary packages/pkg/All shtk

    save_state
}


integration_test_case auto_workflow_reusing_sandbox
auto_workflow_reusing_sandbox_intbody() {
    reuse_bootstrap
    reuse_packages cwrappers digest pkgconf shtk

    # Disable tests to make the build below a bit faster.
    echo "PKG_DEFAULT_OPTIONS=-tests" >extra.mk.conf
    echo "EXTRA_MKCONF='$(pwd)/extra.mk.conf'" >>pkg_comp.conf

    atf_check -o ignore -e ignore pkg_comp -c pkg_comp.conf sandbox-create

    check_files sandbox
    atf_check \
        -o not-match:'Starting build of .*atf-[0-9]' \
        -o match:'Starting build of .*shtk-[0-9]' \
        -o match:'Successfully built .*shtk-[0-9]' \
        -e not-match:'pkg_comp: I: Updating pkgsrc tree' \
        -e match:'pkg_comp: W: Reusing existing sandbox' \
        pkg_comp -c pkg_comp.conf auto -f shtk
    check_files packages/pkg/All/shtk-[0-9]*
    check_files sandbox

    atf_check -o ignore -e ignore pkg_comp -c pkg_comp.conf sandbox-destroy

    save_state
}


integration_test_case logs_workflow
logs_workflow_intbody() {
    reuse_bootstrap
    reuse_packages cwrappers digest

    setup_fetch_from_local_git

    atf_check -o ignore -e ignore pkg_comp -c pkg_comp.conf fetch

    check_files pkgsrc/pkgtools/verifypc/Makefile
    cat >>pkgsrc/pkgtools/verifypc/Makefile <<EOF
pre-extract: always-fail
always-fail: .PHONY
	false
EOF

    atf_check \
        -s exit:1 \
        -o match:'Starting build of .*verifypc' \
        -o match:'Failed to build.*verifypc' \
        -e match:'Failed to build.*verifypc.*detailed logs' \
        pkg_comp -c pkg_comp.conf auto verifypc

    # Check presence of pbulk summary logs.
    test -f bulklog/report.txt || fail "report.txt not found in bulklog"
    test -f bulklog/report.html || fail "report.txt not found in bulklog"

    # Check presence of package-specific logs.
    test -f bulklog/verifypc*/failure || fail "verifypc-specific logs not found"

    save_state
}


atf_init_test_cases() {
    local tests=
    tests="${tests} auto_workflow"
    tests="${tests} auto_workflow_reusing_sandbox"
    tests="${tests} auto_workflow_with_fetch"
    tests="${tests} bootstrap_workflow"
    tests="${tests} build_workflow"
    tests="${tests} fetch_workflow"
    tests="${tests} functional_pkgsrc_after_bootstrap"
    tests="${tests} logs_workflow"

    local i=0
    for t in ${tests}; do
        if [ "${i}" -eq "${INTTEST_SHARD}" ]; then
            atf_add_test_case "${t}"
        fi
        i=$(( (${i} + 1) % ${INTTEST_SHARDS} ))
    done
}
