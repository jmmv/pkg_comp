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

shtk_import pkg_comp_pkgsrc
shtk_import unittest


shtk_unittest_add_fixture expand_packages
expand_packages_fixture() {
    setup() {
        mkdir -p pkgsrc/first/pkg-a
        mkdir -p pkgsrc/second/pkg-b
        mkdir -p pkgsrc/third/pkg-c
        mkdir -p pkgsrc/fourth/pkg-d
    }


    teardown() {
        rm -rf pkgsrc
    }


    shtk_unittest_add_test all_exist_with_categories
    all_exist_with_categories_test() {
        assert_command \
            -o not-match:pkg-a \
            -o match:second/pkg-b \
            -o not-match:pkg-c \
            -o match:fourth/pkg-d \
            pkgsrc_expand_packages pkgsrc second/pkg-b fourth/pkg-d
    }


    shtk_unittest_add_test all_exist_without_categories
    all_exist_without_categories_test() {
        assert_command \
            -o not-match:pkg-a \
            -o match:second/pkg-b \
            -o match:third/pkg-c \
            -o not-match:pkg-d \
            pkgsrc_expand_packages pkgsrc pkg-b pkg-c
    }


    shtk_unittest_add_test some_missing
    some_missing_test() {
        assert_command -s exit:1 \
            -o not-match:first \
            -o match:second/pkg-b \
            -o not-match:second/pkg-a \
            -o not-match:pkg-c \
            -o match:fourth/pkg-d \
            -o not-match:pkg-e \
            -e match:"W: Package first does not exist" \
            -e match:"W: Package second/pkg-a does not exist" \
            -e match:"W: Package pkg-e does not exist" \
            pkgsrc_expand_packages pkgsrc \
            first pkg-b second/pkg-a fourth/pkg-d pkg-e
    }
}
