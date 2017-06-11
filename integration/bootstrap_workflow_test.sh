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

# \file bootstrap_workflow_test.sh
# Integration test for the pkg_comp.sh script.


integration_test_case main
main_intbody() {
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

    atf_check -e ignore pkg_comp -c pkg_comp.conf sandbox-destroy
    save_state
}
