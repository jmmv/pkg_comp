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

# \file auto_workflow_reusing_sandbox_test.sh
# Integration test for the pkg_comp.sh script.


integration_test_case main
main_intbody() {
    reuse_bootstrap
    reuse_packages cwrappers digest pkgconf shtk sysbuild

    # Disable tests to make the build below a bit faster.
    echo "PKG_DEFAULT_OPTIONS=-tests" >extra.mk.conf
    echo "EXTRA_MKCONF='$(pwd)/extra.mk.conf'" >>pkg_comp.conf

    atf_check -o ignore -e ignore pkg_comp -c pkg_comp.conf sandbox-create

    check_files sandbox
    atf_check \
        -o not-match:'Starting build of .*atf-[0-9]' \
        -o match:'Starting build of .*shtk-[0-9]' \
        -o match:'Successfully built .*shtk-[0-9]' \
        -o not-match:'Starting build of .*sysbuild-[0-9]' \
        -o not-match:'Successfully built .*sysbuild-[0-9]' \
        -e not-match:'pkg_comp: I: Updating pkgsrc tree' \
        -e match:'pkg_comp: W: Reusing existing sandbox' \
        pkg_comp -c pkg_comp.conf auto -f shtk
    check_files packages/pkg/All/shtk-[0-9]*
    check_files packages/pkg/All/sysbuild-[0-9]*
    check_files sandbox

    atf_check -o ignore -e ignore pkg_comp -c pkg_comp.conf sandbox-destroy

    save_state
}
