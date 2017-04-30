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

# \file auto_workflow_with_fetch_test.sh
# Integration test for the pkg_comp.sh script.


integration_test_case main
main_inthead() {
    atf_set require.progs "git"
}
main_intbody() {
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


atf_init_test_cases() {
    atf_add_test_case main
}
