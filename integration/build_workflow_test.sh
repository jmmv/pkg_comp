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

# \file build_workflow_test.sh
# Integration test for the pkg_comp.sh script.


integration_test_case main
main_intbody() {
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
