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

# \file functional_pkgsrc_after_bootstrap_test.sh
# Integration test for the pkg_comp.sh script.


integration_test_case main
main_intbody() {
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
