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

# \file admin/bootstrap.sh
# Fetches all pkg_comp components and installs them.
#
# This file must be self-contained so that it can be downloaded from the
# repository and used to install pkg_comp and all necessary components on the
# supported platforms.
#
# The -d flag can be used to customize the location and version of some
# dependencies.  This flag exists purely to support testing this script
# against unreleased versions of those packages and should not be used in
# the general case.


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


# Downloads a file specified by an URL.
#
# \param url The file to download.
# \param file Path to where to save the downloaded file.
download() {
    local url="${1}"; shift
    local file="${1}"; shift

    info "Downloading ${url}"
    local done=no

    case "${url}" in
        /*)
            cp "${url}" "${file}" || err "Failed to copy ${url}"
            done=yes
            ;;
    esac

    if [ "${done}" = no ]; then
        case "$(uname -s)" in
            FreeBSD)
                fetch -o "${file}" "${url}" || err "Failed to download ${url}"
                done=yes
                ;;

            NetBSD)
                ftp -o "${file}" "${url}" || err "Failed to download ${url}"
                done=yes
                ;;
        esac
    fi

    if [ "${done}" = no ]; then
        if which curl >/dev/null; then
            curl -L "${url}" >"${file}.tmp" || err "Failed to download ${url}"
            mv "${file}.tmp" "${file}"
            done=yes
        elif which wget >/dev/null; then
            wget -O "${file}" "${file}" || err "Failed to download ${url}"
            done=yes
        fi
    fi

    [ "${done}" = yes ] \
        || err "Sorry; don't know how to fetch files on your system"
}


# Builds and installs a package.
#
# \param workdir Temporary directory in which to find distfiles, extract them,
#     and run the builds.
# \param distname Basename of the distfile.  The distfile must exist within the
#     given work directory and end in .tar.gz.
# \param ... Extra arguments to the configure script.
build() {
    local workdir="${1}"; shift
    local distname="${1}"; shift

    info "Extracting ${distname}"
    tar -xz -C "${workdir}" -f "${workdir}/${distname}.tar.gz" \
        || err "Failed to extract ${distname}"

    info "Configuring and building ${distname}"
    (
        cd "${workdir}/${distname}" || exit
        ./configure "${@}" || exit
        make || exit
        make install || exit
    ) || err "Failed to install ${distname}; see output for details"
}


# Prints a usage error and a syntax summary.
usage_error() {
    echo "${ProgName}:" "${@}" 1>&2
    echo "Usage: ${ProgName} [-d PKGNAME=URL.tar.gz] [prefix]" 1>&2
    exit 1
}


# Program's entry point.
main() {
    local pkg_comp_url="https://github.com/jmmv/pkg_comp/releases/download/pkg_comp-2.1/pkg_comp-2.1.tar.gz"
    local sandboxctl_url="https://github.com/jmmv/sandboxctl/releases/download/sandboxctl-1.1/sandboxctl-1.1.tar.gz"
    local shtk_url="https://github.com/jmmv/shtk/releases/download/shtk-1.7/shtk-1.7.tar.gz"

    local OPTIND  # Cope with bash failing to reinitialize getopt.
    while getopts ':d:' arg "${@}"; do
        case "${arg}" in
            d)  # Distfile override of the form PKGNAME=URL.tar.gz
                local pkgname="${OPTARG%%=*}"
                local url="${OPTARG#*=}"

                case "${pkgname}" in
                    pkg_comp) pkg_comp_url="${url}" ;;
                    sandboxctl) sandboxctl_url="${url}" ;;
                    shtk) shtk_url="${url}" ;;
                    *) usage_error "Unknown pkgname ${pkgname} in -d flag" ;;
                esac
                ;;
            \?)
                usage_error "Unknown option -${OPTARG} in build"
                ;;
        esac
    done
    shift $((${OPTIND} - 1))

    local prefix
    if [ ${#} -eq 0 ]; then
        prefix=/usr/local
    elif [ ${#} -eq 1 ]; then
        prefix="${1}"
    else
        usage_error "Invalid number of arguments"
    fi

    local pkg_comp_distname="${pkg_comp_url##*/}"
    local sandboxctl_distname="${sandboxctl_url##*/}"
    local shtk_distname="${shtk_url##*/}"

    info "Bootstrapping pkg_comp installation into ${prefix}"

    local tempdir
    tempdir="$(mktemp -d "${TMPDIR:-/tmp}/${ProgName}.XXXXXX" 2>/dev/null)" \
        || err "Failed to create temporary directory"
        echo $tempdir
    trap "rm -rf '${tempdir}'" EXIT

    PATH="${prefix}/bin:${prefix}/sbin:${PATH}"
    export PKG_CONFIG_PATH="${prefix}/lib/pkgconfig"

    if ! which pkg-config >/dev/null >/dev/null || ! which pkgconf >/dev/null
    then
        download \
            https://distfiles.dereferenced.org/pkgconf/pkgconf-1.3.0.tar.gz \
            "${tempdir}/pkgconf-1.3.0.tar.gz"
    fi

    case "$(uname -s)" in
        Darwin)
            download "http://bindfs.org/downloads/bindfs-1.13.6.tar.gz" \
                "${tempdir}/bindfs-1.13.6.tar.gz" || exit 1
            PKG_CONFIG_PATH="${PKG_CONFIG_PATH}:/usr/local/lib/pkgconfig"
            ;;
    esac

    download "${pkg_comp_url}" "${tempdir}/${pkg_comp_distname}"
    download "${sandboxctl_url}" "${tempdir}/${sandboxctl_distname}"
    download "${shtk_url}" "${tempdir}/${shtk_distname}"

    if [ -e "${tempdir}/pkgconf-1.3.0.tar.gz" ]; then
        build "${tempdir}" pkgconf-1.3.0 --prefix="${tempdir}/tools" || exit 1
        export PKG_CONFIG="${tempdir}/tools/bin/pkgconf"
    fi
    if [ -e "${tempdir}/bindfs-1.13.6.tar.gz" ]; then
        build "${tempdir}" bindfs-1.13.6 --prefix="${prefix}" || exit 1
    fi
    build "${tempdir}" "${shtk_distname%.tar.gz}" \
        --prefix="${prefix}" SHTK_SHELL=/bin/sh || exit 1
    build "${tempdir}" "${sandboxctl_distname%.tar.gz}" \
        --prefix="${prefix}" --with-atf=no BINDFS="${prefix}/bin/bindfs" \
        || exit 1
    build "${tempdir}" "${pkg_comp_distname%.tar.gz}" \
        --prefix="${prefix}" --with-atf=no || exit 1

    info "Bootstrapping successful"
    info "pkg_comp is available at: ${prefix}/sbin/pkg_comp"
}


main "${@}"
