#! __ATF_SH__
# Copyright 2013 Google Inc.
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

# \file pkg_comp_test.sh
# Tests for the pkg_comp.sh script.
#
# The tests in this script are intended to be fast to run but, for the most
# part, use only mocks to verify that the main program logic works.


# Paths to installed files.
#
# Can be overriden for test purposes only.
: ${PKG_COMP_ETCDIR="__PKG_COMP_ETCDIR__"}
: ${PKG_COMP_SHAREDIR="__PKG_COMP_SHAREDIR__"}


# Path to a local cvsroot for testing purposes.
MOCK_CVSROOT=":local:$(pwd)/cvsroot"


# Creates a fake program that records its invocations for later processing.
#
# The fake program, when invoked, will append its arguments to a commands.log
# file in the test case's work directory.
#
# \param binary The path to the program to create.
# \param delegate If set to 'yes', execute the real program afterwards.
create_mock_binary() {
    local binary="${1}"; shift
    local delegate=no
    [ ${#} -eq 0 ] || { delegate="${1}"; shift; }

    cat >"${binary}" <<EOF
#! /bin/sh

logfile="${HOME}/commands.log"
echo "Command: \${0##*/}" >>"\${logfile}"
echo "Directory: \$(pwd)" >>"\${logfile}"
for arg in "\${@}"; do
    echo "Arg: \${arg}" >>"\${logfile}"
done
    echo >>"\${logfile}"
EOF

    if [ "${delegate}" = yes ]; then
        cat >>"${binary}" <<EOF
PATH="${PATH}"
exec "\${0##*/}" "\${@}"
EOF
    fi

    chmod +x "${binary}"
}


# Creates a fake CVS repository with a pkgsrc module.
#
# \param repository Path to the repository to create.
create_mock_cvsroot() {
    local repository="${1}"; shift

    atf_check -o ignore -e ignore cvs -d "${repository}" init

    mkdir pkgsrc
    cd pkgsrc
    create_mock_binary build.sh
    echo "first revision" >file-in-pkgsrc
    cvs -d "${repository}" import -m "Import." pkgsrc VENDOR_TAG release_tag
    cd -
    rm -rf pkgsrc
}


atf_test_case config__builtins
config__builtins_body() {
    mkdir sandbox-modules
    export SANDBOXCTL_MODULESDIR="$(pwd)/sandbox-modules"

    cat >expout <<EOF
AUTO_PACKAGES is undefined
CVSROOT = :ext:anoncvs@anoncvs.NetBSD.org:/cvsroot
CVSTAG is undefined
DISTDIR = /usr/pkgsrc/distfiles
EXTRA_MKCONF is undefined
LOCALBASE = /usr/pkg
NJOBS = 99
PACKAGES = /usr/pkgsrc/packages
PBULK_PACKAGES = /usr/pkgsrc/packages/pbulk
PKG_DBDIR = /usr/pkg/libdata/pkgdb
PKGSRCDIR = /usr/pkgsrc
SANDBOX_CONFFILE is undefined
SYSCONFDIR = /etc
UPDATE_SOURCES = true
VARBASE = /var

SANDBOX_ROOT is undefined
SANDBOX_TYPE = empty
EOF
    atf_check -o file:expout env SHTK_HW_NCPUS=99 pkg_comp -c /dev/null config
}


atf_test_case config__path__components
config__path__components_body() {
    mkdir system
    export PKG_COMP_ETCDIR="$(pwd)/system"

    echo "CVSTAG=tag1" >my-file
    atf_check -o match:"CVSTAG = tag1" pkg_comp -c ./my-file config
}


atf_test_case config__path__extension
config__path__extension_body() {
    mkdir system
    export PKG_COMP_ETCDIR="$(pwd)/system"

    echo "CVSTAG=tag2" >my-file.conf
    atf_check -o match:"CVSTAG = tag2" pkg_comp -c my-file.conf config
}


atf_test_case config__name__system_directory
config__name__system_directory_body() {
    mkdir system
    export PKG_COMP_ETCDIR="$(pwd)/system"

    echo "CVSROOT='custom-root'" >system/foo.conf
    atf_check -o match:"CVSROOT = custom-root" pkg_comp -c foo config
}


atf_test_case config__name__not_found
config__name__not_found_body() {
    mkdir system
    export PKG_COMP_ETCDIR="$(pwd)/system"

    cat >experr <<EOF
pkg_comp: E: Cannot locate configuration named 'foobar'
Type 'man pkg_comp' for help
EOF
    atf_check -s exit:1 -o empty -e file:experr pkg_comp -c foobar config
}


atf_test_case config__overrides
config__overrides_body() {
    mkdir sandbox-modules
    export SANDBOXCTL_MODULESDIR="$(pwd)/sandbox-modules"

    cat >custom.conf <<EOF
CVSROOT=the-root
CVSTAG=the-tag
PKGSRCDIR=/usr/pkgsrc
EOF
    cat >sandbox.conf <<EOF
SANDBOX_ROOT=/non-existent/location
EOF

    cat >expout <<EOF
AUTO_PACKAGES is undefined
CVSROOT = foo bar
CVSTAG = tag123
DISTDIR = /usr/pkgsrc/distfiles
EXTRA_MKCONF is undefined
LOCALBASE = /usr/pkg
NJOBS = 80
PACKAGES = /usr/pkgsrc/packages
PBULK_PACKAGES = /usr/pkgsrc/packages/pbulk
PKG_DBDIR = /usr/pkg/libdata/pkgdb
PKGSRCDIR is undefined
SANDBOX_CONFFILE = $(pwd)/sandbox.conf
SYSCONFDIR = /etc
UPDATE_SOURCES = true
VARBASE = /var

SANDBOX_ROOT = /non-existent/location
SANDBOX_TYPE = empty
EOF
    atf_check -o file:expout pkg_comp -c custom.conf -o CVSROOT="foo bar" \
        -o CVSTAG=tag123 -o NJOBS=80 -o PKGSRCDIR= \
        -o SANDBOX_CONFFILE="$(pwd)/sandbox.conf" config
}


atf_test_case config__too_many_args
config__too_many_args_body() {
    cat >experr <<EOF
pkg_comp: E: config does not take any arguments
Type 'man pkg_comp' for help
EOF
    atf_check -s exit:1 -e file:experr pkg_comp -c /dev/null config foo
}


atf_test_case fetch__checkout
fetch__checkout_head() {
    atf_set require.progs cvs
}
fetch__checkout_body() {
    create_mock_cvsroot "${MOCK_CVSROOT}"
    cat >test.conf <<EOF
CVSROOT="${MOCK_CVSROOT}"
PKGSRCDIR="$(pwd)/checkout/pkgsrc"
EOF

    atf_check -o ignore -e ignore pkg_comp -c test.conf fetch
    test -f checkout/pkgsrc/file-in-pkgsrc || atf_fail "pkgsrc not checked out"
}


atf_test_case fetch__update
fetch__update_head() {
    atf_set require.progs cvs
}
fetch__update_body() {
    create_mock_cvsroot "${MOCK_CVSROOT}"
    cat >test.conf <<EOF
CVSROOT="${MOCK_CVSROOT}"
PKGSRCDIR="$(pwd)/checkout/pkgsrc"
EOF

    mkdir checkout
    cd checkout
    atf_check -o ignore -e ignore cvs -d"${MOCK_CVSROOT}" checkout -P pkgsrc
    cd -

    cp -rf checkout/pkgsrc pkgsrc-copy
    cd pkgsrc-copy
    echo "second revision" >file-in-pkgsrc
    cvs commit -m "Second revision."
    cd -

    test -f checkout/pkgsrc/file-in-pkgsrc || atf_fail "pkgsrc not present yet"
    if grep "second revision" checkout/pkgsrc/file-in-pkgsrc >/dev/null; then
        atf_fail "second revision already present"
    fi

    atf_check -o ignore -e ignore pkg_comp -c test.conf fetch

    grep "second revision" checkout/pkgsrc/file-in-pkgsrc >/dev/null \
        || atf_fail "pkgsrc not updated"
}


atf_test_case fetch__hooks__ok
fetch__hooks__ok_head() {
    atf_set require.progs cvs
}
fetch__hooks__ok_body() {
    create_mock_cvsroot "${MOCK_CVSROOT}"
    cat >test.conf <<EOF
CVSROOT="${MOCK_CVSROOT}"
PKGSRCDIR="$(pwd)/checkout/pkgsrc"

post_fetch_hook() {
    test -d "\${PKGSRCDIR}" || return 1
    echo "Hook after fetch"
}
EOF

    atf_check -o save:stdout -e ignore pkg_comp -c test.conf fetch
    test -f checkout/pkgsrc/file-in-pkgsrc || atf_fail "pkgsrc not checked out"

    cat >exp_order <<EOF
Hook after fetch
EOF
    atf_check -o file:exp_order grep '^Hook' stdout
}


atf_test_case fetch__hooks__post_fail
fetch__hooks__post_fail_head() {
    atf_set require.progs cvs
}
fetch__hooks__post_fail_body() {
    create_mock_cvsroot "${MOCK_CVSROOT}"
    cat >test.conf <<EOF
CVSROOT="${MOCK_CVSROOT}"
PKGSRCDIR="$(pwd)/checkout/pkgsrc"

post_fetch_hook() {
    echo "Hook after fetch"
    false
}
EOF

    atf_check -s exit:1 -o save:stdout -e save:stderr \
        pkg_comp -c test.conf fetch
    test -f checkout/pkgsrc/file-in-pkgsrc || atf_fail "pkgsrc not checked out"
    grep 'post_fetch_hook returned an error' stderr || \
        atf_fail "post_fetch_hook didn't seem to fail"

    cat >exp_order <<EOF
Hook after fetch
EOF
    atf_check -o file:exp_order grep '^Hook' stdout
}


atf_test_case fetch__too_many_args
fetch__too_many_args_body() {
    cat >experr <<EOF
pkg_comp: E: fetch does not take any arguments
Type 'man pkg_comp' for help
EOF
    atf_check -s exit:1 -e file:experr pkg_comp -c /dev/null fetch foo
}


atf_test_case sandboxctl__all_commands_delegation
sandboxctl__all_commands_delegation_body() {
    cat >sandboxctl <<EOF
#! /bin/sh
printf args:
while [ \${#} -gt 0 ]; do
    printf " ~\${1}~"
    shift
done
echo
exit 42
EOF
    chmod +x sandboxctl
    export SANDBOXCTL="$(pwd)/sandboxctl"

    for cmd in config create destroy mount run shell unmount; do
        atf_check -s exit:42 -o save:out pkg_comp -c /dev/null \
            "sandbox-${cmd}" abc
        echo "args: ~-c${TMPDIR}/pkg_comp.ZZZZZZ~ ~${cmd}~ ~abc~" >expout
        atf_check -o file:expout \
            sed -e "s,/pkg_comp\.......,/pkg_comp.ZZZZZZ," out
    done

    atf_check -s exit:42 -o save:out pkg_comp -c /dev/null -v sandbox-create
    echo "args: ~-c${TMPDIR}/pkg_comp.ZZZZZZ~ ~-v~ ~create~" >expout
    atf_check -o file:expout sed -e "s,/pkg_comp\.......,/pkg_comp.ZZZZZZ," out
}


atf_test_case sandboxctl__create_destroy_integration
sandboxctl__create_destroy_integration_body() {
    cat >pkg_comp.conf <<EOF
DISTDIR="$(pwd)/distfiles"
PACKAGES="$(pwd)/packages/pkg"
PBULK_PACKAGES="$(pwd)/packages/pbulk"
PKGSRCDIR="$(pwd)/pkgsrc"
SANDBOX_CONFFILE="$(pwd)/sandbox.conf"
EOF
    cat >sandbox.conf <<EOF
SANDBOX_ROOT="$(pwd)/sandbox"
SANDBOX_TYPE=empty
EOF

    atf_check -s exit:1 -e match:'sandboxctl.* create.* arguments' \
        pkg_comp -c pkg_comp.conf sandbox-create foo bar

    for dir in distfiles packages pkgsrc sandbox; do
        [ ! -d "${dir}" ] || atf_fail "${dir} should not yet exist"
    done

    atf_check pkg_comp -c pkg_comp.conf sandbox-create
    for dir in distfiles packages pkgsrc sandbox; do
        [ -d "${dir}" ] || atf_fail "${dir} was not created"
    done
    atf_check pkg_comp -c pkg_comp.conf sandbox-destroy
    [ -d distfiles ] || atf_fail "distfiles was destroyed by mistake"
    [ -d packages ] || atf_fail "packages was destroyed by mistake"
    [ -d pkgsrc ] || atf_fail "pkgsrc was destroyed by mistake"
    [ ! -d sandbox ] || atf_fail "sandbox was not destroyed"
}


atf_test_case no_command
no_command_body() {
    cat >experr <<EOF
pkg_comp: E: No command specified
Type 'man pkg_comp' for help
EOF
    atf_check -s exit:1 -e file:experr pkg_comp
}


atf_test_case unknown_command
unknown_command_body() {
    cat >experr <<EOF
pkg_comp: E: Unknown command foo
Type 'man pkg_comp' for help
EOF
    atf_check -s exit:1 -e file:experr pkg_comp foo
}


atf_test_case unknown_flag
unknown_flag_body() {
    cat >experr <<EOF
pkg_comp: E: Unknown option -Z
Type 'man pkg_comp' for help
EOF
    atf_check -s exit:1 -e file:experr pkg_comp -Z
}


atf_init_test_cases() {
    atf_add_test_case config__builtins
    atf_add_test_case config__path__components
    atf_add_test_case config__path__extension
    atf_add_test_case config__name__system_directory
    atf_add_test_case config__name__not_found
    atf_add_test_case config__overrides
    atf_add_test_case config__too_many_args

    atf_add_test_case fetch__checkout
    atf_add_test_case fetch__update
    atf_add_test_case fetch__hooks__ok
    atf_add_test_case fetch__hooks__post_fail
    atf_add_test_case fetch__too_many_args

    atf_add_test_case sandboxctl__all_commands_delegation
    atf_add_test_case sandboxctl__create_destroy_integration

    atf_add_test_case no_command
    atf_add_test_case unknown_command
    atf_add_test_case unknown_flag
}
