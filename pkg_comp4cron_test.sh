# Copyright 2012 Google Inc.
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

# \file pkg_comp4cron_test.sh
# Integration tests for the pkg_comp4cron.sh script.

shtk_import unittest


# Creates a fake program that records its invocations for later processing.
#
# The fake program, when invoked, will append its arguments to a commands.log
# file in the test case's work directory.
#
# \param binary The path to the program to create.
# \param get_stdin Whether to capture stdin or not.
create_mock_binary() {
    local binary="${1}"; shift
    local get_stdin="${1}"; shift

    cat >"${binary}" <<EOF
#! /bin/sh

logfile="${HOME}/commands.log"
echo "Command: \${0##*/}" >>"\${logfile}"
for arg in "\${@}"; do
    echo "Arg: \${arg}" >>"\${logfile}"
done
    [ "${get_stdin}" = no ] || sed -e 's,^,stdin: ,' >>"\${logfile}"
    echo >>"\${logfile}"
EOF
    chmod +x "${binary}"
}


setup_mocks() {
    mkdir bin
    create_mock_binary bin/mail yes
    create_mock_binary bin/pkg_comp no
    PATH="$(pwd)/bin:${PATH}"
    PKG_COMP_BINDIR="$(pwd)/bin"; export PKG_COMP_BINDIR
}


shtk_unittest_add_test no_args
no_args_test() {
    setup_mocks
    assert_command pkg_comp4cron

    assert_file stdin commands.log <<EOF
Command: pkg_comp

EOF
}


shtk_unittest_add_test some_args
some_args_test() {
    setup_mocks
    assert_command pkg_comp4cron -- -k -Z foo bar

    assert_file stdin commands.log <<EOF
Command: pkg_comp
Arg: -k
Arg: -Z
Arg: foo
Arg: bar

EOF
}


shtk_unittest_add_test pkg_comp_fails
pkg_comp_fails_test() {
    setup_mocks
    for number in $(seq 150); do
        echo "echo line ${number}" >>bin/pkg_comp
    done
    echo "exit 1" >>bin/pkg_comp

    assert_command pkg_comp4cron a

    name="$(cd pkg_comp/log && echo pkg_comp4cron.*.log)"
    cat >expout <<EOF
Command: pkg_comp
Arg: a

Command: mail
Arg: -s
Arg: pkg_comp failure report
Arg: ${USER}
stdin: The following command has failed:
stdin: 
stdin:     $(pwd)/bin/pkg_comp a
stdin: 
stdin: The output of the failed command has been left in:
stdin: 
stdin:     $(pwd)/pkg_comp/log/${name}
stdin: 
stdin: The last 100 of the log follow:
stdin: 
EOF
    for number in $(seq 51 150); do
        echo "stdin: line ${number}" >>expout
    done
    echo >>expout
    assert_file file:expout commands.log
}


shtk_unittest_add_test custom_flags
custom_flags_test() {
    setup_mocks
    echo "exit 1" >>bin/pkg_comp

    assert_command pkg_comp4cron -l path/to/logs -r somebody@example.net

    name="$(cd path/to/logs && echo pkg_comp4cron.*.log)"
    assert_file stdin commands.log <<EOF
Command: pkg_comp

Command: mail
Arg: -s
Arg: pkg_comp failure report
Arg: somebody@example.net
stdin: The following command has failed:
stdin: 
stdin:     $(pwd)/bin/pkg_comp
stdin: 
stdin: The output of the failed command has been left in:
stdin: 
stdin:     $(pwd)/path/to/logs/${name}
stdin: 
stdin: The last 100 of the log follow:
stdin: 

EOF
}


shtk_unittest_add_test capture_out_and_err
capture_out_and_err_test() {
    setup_mocks
    echo "echo foo" >>bin/pkg_comp
    echo "echo bar 1>&2" >>bin/pkg_comp
    echo "exit 1" >>bin/pkg_comp

    assert_command pkg_comp4cron

    expect_file match:"stdin: foo" commands.log
    expect_file match:"stdin: bar" commands.log
}


shtk_unittest_add_test unknown_flag
unknown_flag_test() {
    cat >experr <<EOF
pkg_comp4cron: E: Unknown option -Z
Type 'man pkg_comp4cron' for help
EOF
    assert_command -s exit:1 -e file:experr pkg_comp4cron -Z
}


shtk_unittest_add_test missing_argument
missing_argument_test() {
    cat >experr <<EOF
pkg_comp4cron: E: Missing argument to option -l
Type 'man pkg_comp4cron' for help
EOF
    assert_command -s exit:1 -e file:experr pkg_comp4cron -l
}
