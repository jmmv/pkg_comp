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

shtk_import pkg_comp_git
shtk_import unittest


# Creates a local Git repository with some files.
#
# \param dir Path to the repository to create.
# \param branch Name of the branch to create.  Avoid "master" to ensure our
#     functions work with the non-default branch.
init_git_repository() {
    local dir="${1}"; shift
    local branch="${1}"; shift

    assert_command -o ignore -e ignore git init --bare "${dir}"

    mkdir work
    cd work
    assert_command -o ignore -e ignore git init
    assert_command -o ignore -e ignore git checkout -b "${branch}"
    echo "first revision" >the-file
    assert_command -o ignore -e ignore git add the-file
    assert_command -o ignore -e ignore git commit -a -m "First revision"
    assert_command -o ignore -e ignore git push -u "file://${dir}" "${branch}"
    cd -
    rm -rf work
}


# Commits and pushes pending changes in a working copy.
#
# \param dir Path to the git working copy.
commit_and_push() {
    local dir="${1}"; shift

    (
        cd "${dir}"
        git commit -a -m "Changes." || exit 1
        git push || exit 1
    ) || fail "Failed to modify repository"
}


shtk_unittest_add_fixture fetch
fetch_fixture() {
    setup() {
        REPOSITORY_DIR="$(pwd)/repository"
        REPOSITORY_URL="file://${REPOSITORY_DIR}"
        init_git_repository "${REPOSITORY_DIR}" trunk
    }


    teardown() {
        rm -rf "${REPOSITORY_DIR}"
    }


    shtk_unittest_add_test ok
    ok_test() {
        expect_command -o ignore -e ignore \
            pkg_comp_git_fetch "${REPOSITORY_URL}" trunk clone1
        grep "first revision" clone1/the-file >/dev/null \
            || fail "Unexpected version found"

        cp -r clone1 clone2
        echo "second revision" >clone2/the-file
        commit_and_push clone2
        rm -rf clone2

        grep "first revision" clone1/the-file >/dev/null \
            || fail "Unexpected version found"
        expect_command -o ignore -e ignore \
            pkg_comp_git_fetch "${REPOSITORY_URL}" trunk clone1
        grep "second revision" clone1/the-file >/dev/null \
            || fail "Unexpected version found"
    }
}


shtk_unittest_add_fixture checkout
checkout_fixture() {
    setup() {
        REPOSITORY_DIR="$(pwd)/repository"
        REPOSITORY_URL="file://${REPOSITORY_DIR}"
    }


    teardown() {
        rm -rf "${REPOSITORY_DIR}"
    }


    shtk_unittest_add_test ok
    ok_test() {
        init_git_repository "${REPOSITORY_DIR}" trunk
        expect_command -o ignore -e ignore \
            pkg_comp_git_clone "${REPOSITORY_URL}" trunk clone
        grep "first revision" clone/the-file >/dev/null \
            || fail "Unexpected version found"
    }


    shtk_unittest_add_test already_exists
    already_exists_test() {
        mkdir -p missing-dir
        expect_command -s exit:1 \
            -e match:"Cannot clone into .*missing-dir.* exists" \
            pkg_comp_git_clone "${REPOSITORY_URL}" trunk missing-dir
    }


    shtk_unittest_add_test git_fails
    git_fails_test() {
        init_git_repository "${REPOSITORY_DIR}" trunk
        expect_command -s exit:1 -e match:"Git clone failed" \
            pkg_comp_git_clone "${REPOSITORY_URL}" non-existent dir
        [ ! -e dir ] || fail "Clone directory created and left behind"
    }
}


shtk_unittest_add_fixture update
update_fixture() {
    setup() {
        REPOSITORY_DIR="$(pwd)/repository"
        REPOSITORY_URL="file://${REPOSITORY_DIR}"
    }


    teardown() {
        rm -rf "${REPOSITORY_DIR}"
    }


    shtk_unittest_add_test ok
    ok_test() {
        init_git_repository "${REPOSITORY_DIR}" trunk

        assert_command -o ignore -e ignore \
            git clone -b trunk "${REPOSITORY_URL}" first
        assert_command -o ignore -e ignore \
            git clone -b trunk "${REPOSITORY_URL}" copy

        expect_command -o ignore -e ignore \
            pkg_comp_git_update "${REPOSITORY_URL}" trunk first
        grep "first revision" first/the-file >/dev/null \
            || fail "Unexpected version found"

        echo "second revision" >copy/the-file
        commit_and_push copy

        expect_command -o ignore -e ignore \
            pkg_comp_git_update "${REPOSITORY_URL}" trunk first
        grep "second revision" first/the-file >/dev/null \
            || fail "Unexpected version found"
    }


    shtk_unittest_add_test stash_changes__ok
    stash_changes__ok_test() {
        init_git_repository "${REPOSITORY_DIR}" trunk

        # Make the-file contain multiple lines so that we can perform
        # independent edits in two places.
        assert_command -o ignore -e ignore \
            git clone -b trunk "${REPOSITORY_URL}" first
        seq 10 >first/the-file
        commit_and_push first

        # Update a line in the-file and push it to the repository.
        assert_command -o ignore -e ignore \
            git clone -b trunk "${REPOSITORY_URL}" copy
        sed s,^9$,90, copy/the-file >copy/the-file.new
        mv copy/the-file.new copy/the-file
        commit_and_push copy

        # Modify a different line in the-file that is far enough from the other
        # line we modified so that the two edits don't conflict, and leave the
        # changes uncommitted.
        sed s,^2$,20, first/the-file >first/the-file.new
        mv first/the-file.new first/the-file
        expect_command -o ignore -e ignore \
            pkg_comp_git_update "${REPOSITORY_URL}" trunk first

        # Sanity-check that our edits remain.
        cat >expout <<EOF
1
20
3
4
5
6
7
8
90
10
EOF
        expect_command -o file:expout cat first/the-file

        # Sanity-check that our uncommitted changes are still uncommitted.
        (
            cd first
            git status --porcelain >../status
        ) || fail "git status failed"
        cat >expout <<EOF
 M the-file
EOF
        expect_command -o file:expout cat status
    }


    shtk_unittest_add_test stash_changes__conflict
    stash_changes__conflict_test() {
        init_git_repository "${REPOSITORY_DIR}" trunk

        # Make the-file contain multiple lines so that we can perform
        # independent edits in two places.
        assert_command -o ignore -e ignore \
            git clone -b trunk "${REPOSITORY_URL}" first
        seq 10 >first/the-file
        commit_and_push first

        # Update a line in the-file and push it to the repository.
        assert_command -o ignore -e ignore \
            git clone -b trunk "${REPOSITORY_URL}" copy
        sed s,^9$,90, copy/the-file >copy/the-file.new
        mv copy/the-file.new copy/the-file
        commit_and_push copy

        # Modify a different line in the-file that is close enough to the other
        # line we modified so that the two edits conflict, and leave the changes
        # uncommitted.
        sed s,^8$,80, first/the-file >first/the-file.new
        mv first/the-file.new first/the-file
        expect_command -s exit:1 -o ignore -e ignore \
            pkg_comp_git_update "${REPOSITORY_URL}" trunk first

        # Check that the file is left behind with conflict markers.
        grep '<<<<' first/the-file || fail "No conflict markers found"
    }


    shtk_unittest_add_test switch_branch
    switch_branch_test() {
        init_git_repository "${REPOSITORY_DIR}" trunk

        assert_command -o ignore -e ignore \
            git clone -b trunk "${REPOSITORY_URL}" first
        (
            cd first
            git checkout -b other-trunk
            echo "alternate revision" >the-file
            git commit -a -m "Other branch" || exit 1
            git push "${REPOSITORY_URL}" other-trunk || exit 1

            git checkout trunk || exit 1
        ) || fail "Failed to create new branch"

        grep "first revision" first/the-file >/dev/null \
            || fail "Unexpected version found"
        expect_command -o ignore -e ignore \
            pkg_comp_git_update "${REPOSITORY_URL}" other-trunk first
        grep "alternate revision" first/the-file >/dev/null \
            || fail "Unexpected version found"
    }


    shtk_unittest_add_test does_not_exist
    does_not_exist_test() {
        expect_command -s exit:1 -e match:"Cannot update src; .*not exist" \
            pkg_comp_git_update "${REPOSITORY_URL}" trunk src
    }


    shtk_unittest_add_test git_fails
    git_fails_test() {
        init_git_repository "${REPOSITORY_DIR}" trunk
        assert_command -o ignore -e ignore \
            git clone -b trunk "${REPOSITORY_URL}" work
        expect_command -s exit:1 -e match:"Git fetch failed" \
            pkg_comp_git_update "${REPOSITORY_URL}" bad-branch work
    }
}
