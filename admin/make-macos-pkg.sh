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

# \file admin/make-macos-pkg.sh
# Builds a self-installer package for macOS.
#
# This script must be run with root privileges because we install the
# software under /usr/local.
#
# TODO(jmmv): A lot of the logic in this script should be moved into either
# separate files or into pkg_comp proper.  For example, the cron job
# manipulation code may belong into pkg_comp as user-facing commands, and
# the list.txt parsing should belong in the default configuration.


# Directory name of the running script.
DirName="$(dirname "${0}")"


# Base name of the running script.
ProgName="${0##*/}"


# Prints the given error message to stderr and exits.
#
# \param ... The message to print.
err() {
    echo "${ProgName}: E: $*" 1>&2
    exit 1
}


# Prints the given informational message to stderr.
#
# \param ... The message to print.
info() {
    echo "${ProgName}: I: $*" 1>&2
}


# Creates the package scripts.
#
# \param dir Directory in which to store the scripts.
write_scripts() {
    local dir="${1}"; shift

    mkdir -p "${dir}"
    cat >"${dir}/postinstall" <<EOF
#! /bin/sh

for pkg in sandboxctl pkg_comp; do
    for eg in /usr/local/share/examples/\${pkg}/*; do
        real="/usr/local/etc/\${pkg}/\${eg##*/}"
        if [ -e "\${real}" ]; then
            cmp -s "\${eg}" "\${real}" || cp "\${eg}" "\${real}.new"
        else
            cp "\${eg}" "\${real}"
        fi
    done
done

tempfile="\$(mktemp "\${TMPDIR:-/tmp}/pkg_comp.XXXXXX")"
if ! crontab -u root -l >>"\${tempfile}"; then
    cat >>"\${tempfile}" <<_EOF_
PATH=/usr/bin:/usr/sbin:/bin:/sbin
SHELL=/bin/sh

# Cheatsheet: minute hour day-of-month month day-of-week(0,7=Sun)
_EOF_
fi

if ! grep /usr/local/sbin/pkg_comp4cron "\${tempfile}" >/dev/null; then
    echo "@daily /usr/local/sbin/pkg_comp4cron -l /var/pkg_comp/log" \
        "-- -c /usr/local/etc/pkg_comp/default.conf auto" \
        >>"\${tempfile}"
    crontab -u root - <"\${tempfile}"
fi
rm -f "\${tempfile}"
EOF
    chmod +x "${dir}/postinstall"
}


# Sets a variable in a configuration file.
#
# \param file Path to the file to edit.
# \param var Variable to set.
# \param value Value to set the variable to.
edit_config() {
    local file="${1}"; shift
    local var="${1}"; shift
    local value="${1}"; shift

    sed -E "s,^#?${var}=.*$,${var}=\"${value}\",g" <"${file}" >"${file}.new"
    mv "${file}.new" "${file}"
}


# Modifies the fresh pkg_comp installation for our packaging needs.
#
# \param root Path to the new file system root used to build the package.
configure_root() {
    local root="${1}"; shift

    mkdir -p "${root}/etc/paths.d"
    cat >"${root}/etc/paths.d/pkg_comp" <<EOF
/usr/local/bin
/usr/local/sbin
/opt/pkg/bin
/opt/pkg/sbin
EOF

    for dir in sandboxctl pkg_comp; do
        mkdir -p "${root}/usr/local/share/examples/${dir}"
        mv "${root}/usr/local/etc/${dir}"/* \
            "${root}/usr/local/share/examples/${dir}"
    done

    # TODO(jmmv): We should ship this ourselves as part of the pkg_comp release
    # and use the file here and in pkgsrc's pkg_comp-cron.  Maybe even change
    # the semantics of the AUTO_PACKAGES variable to point to a file and handle
    # this internally for better file parsing.
    cat >"${root}/usr/local/share/examples/pkg_comp/list.txt" <<EOF
# Packages to build automatically.
#
# List one package per line, using bare names or the category/name syntax.

#pkgtools/pkgin
#tmux
EOF

    mkdir -p "${root}/var/pkg_comp"
    mkdir -p "${root}/var/pkg_comp/log"

    local f="${root}/usr/local/share/examples/pkg_comp/default.conf"
    edit_config "${f}" FETCH_VCS git
    edit_config "${f}" PKGSRCDIR /var/pkg_comp/pkgsrc
    edit_config "${f}" DISTDIR /var/pkg_comp/distfiles
    edit_config "${f}" PACKAGES /var/pkg_comp/packages
    edit_config "${f}" PBULK_PACKAGES /var/pkg_comp/pbulk-packages
    edit_config "${f}" LOCALBASE /opt/pkg
    edit_config "${f}" PKG_DBDIR /opt/pkg/libdata/pkgdb
    edit_config "${f}" SYSCONFDIR /opt/pkg/etc
    edit_config "${f}" VARBASE /opt/pkg/var
    edit_config "${f}" \
        AUTO_PACKAGES "\$(grep -v ^# /usr/local/etc/pkg_comp/list.txt)"

    local f="${root}/usr/local/share/examples/pkg_comp/sandbox.conf"
    edit_config "${f}" SANDBOX_ROOT /var/pkg_comp/sandbox

    mkdir -p "${root}/usr/local/libexec/pkg_comp"
    cat >"${root}/usr/local/libexec/pkg_comp/uninstall.sh" <<EOF
#! /bin/sh

tempfile="\$(mktemp "\${TMPDIR:-/tmp}/pkg_comp.XXXXXX")"
if crontab -u root -l >>"\${tempfile}"; then
    if grep /usr/local/sbin/pkg_comp "\${tempfile}" >/dev/null; then
        tempfile2="\$(mktemp "\${TMPDIR:-/tmp}/pkg_comp.XXXXXX")"
        grep -v /usr/local/sbin/pkg_comp "\${tempfile}" >>"\${tempfile2}"
        crontab -u root "\${tempfile2}"
        rm -f "\${tempfile2}"
    fi
fi
rm -f "\${tempfile}"

cd /
for f in \$(tail -r /usr/local/share/pkg_comp/manifest); do
    if [ ! -d "\${f}" ]; then
        rm "\${f}"
    else
        rmdir "\${f}"
    fi
done
EOF
    chmod +x "${root}/usr/local/libexec/pkg_comp/uninstall.sh"

    ( cd "${root}" && find . >"${root}/usr/local/share/pkg_comp/manifest" )
}


# Program's entry point.
main() {
    if [ ${#} -ne 0 ]; then
        echo "${ProgName}: E: No arguments allowed" 1>&2
        echo "Usage: ${ProgName}" 1>&2
        exit 1
    fi

    [ "$(uname -s)" = Darwin ] || err "This script is for macOS only"
    [ -x "${DirName}/bootstrap.sh" ] || err "bootstrap.sh not found; make" \
        "sure to run this from a cloned repository"
    [ "$(id -u)" -eq 0 ] || err "Must be run as root"

    local tempdir
    tempdir="$(mktemp -d "${TMPDIR:-/tmp}/${ProgName}.XXXXXX" 2>/dev/null)" \
        || err "Failed to create temporary directory"
    trap "rm -rf '${tempdir}'" EXIT

    export PKG_CONFIG_PATH=/usr/local/lib/pkgconfig  # For OSXFUSE.

    # Bootstrap under a clean prefix to generate a manifest of all the files
    # required by our installation.
    info "Doing temporary bootstrap to generate file manifest"
    "${DirName}/bootstrap.sh" "${tempdir}/prefix" || err "Bootstrap failed"
    ( cd "${tempdir}/prefix" && find . \! -type d ) >"${tempdir}/manifest"

    # Bootstrap under the final location.
    info "Doing real bootstrap under prefix"
    "${DirName}/bootstrap.sh" /usr/local || err "Bootstrap failed"

    info "Generating package root"
    mkdir -p "${tempdir}/root/usr/local"
    tar -cp -C /usr/local -f - $(cat "${tempdir}/manifest") | \
        tar -xp -C "${tempdir}/root/usr/local" -f -
    configure_root "${tempdir}/root"

    info "Removing pkg_comp installation from /usr/local"
    ( cd /usr/local && rm $(cat "${tempdir}/manifest") )

    local version="$(grep '^Changes in version' \
        "${tempdir}/prefix/share/doc/pkg_comp/NEWS" \
        | head -n 1 | awk '{print $4}')"
    local revision="$(date +%Y%m%d)"
    local pkgversion="${version}-${revision}"
    local pkgfile="pkg_comp-${pkgversion}-macos.pkg"

    info "Building package ${pkgfile}"
    write_scripts "${tempdir}/scripts"
    pkgbuild \
        --identifier com.github.jmmv.pkg_comp \
        --root "${tempdir}/root" \
        --scripts "${tempdir}/scripts" \
        --version "${pkgversion}" \
        "${pkgfile}"
}


main "${@}"
