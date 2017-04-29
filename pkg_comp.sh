# Copyright 2013 Google Inc.
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

# \file pkg_comp.sh
# Entry point and main program logic.

shtk_import cleanup
shtk_import cli
shtk_import config
shtk_import cvs
shtk_import hw
: ${PKG_COMP_SHTK_MODULESDIR:="__PKG_COMP_SHTK_MODULESDIR__"}
SHTK_MODULESPATH="${PKG_COMP_SHTK_MODULESDIR}" shtk_import git
SHTK_MODULESPATH="${PKG_COMP_SHTK_MODULESDIR}" shtk_import pkgsrc


# List of valid configuration variables.
#
# Please remember to update pkg_comp.conf(5) if you change this list.
PKG_COMP_CONFIG_VARS="AUTO_PACKAGES CVS_ROOT CVS_TAG DISTDIR EXTRA_MKCONF
                      FETCH_VCS GIT_BRANCH GIT_URL LOCALBASE NJOBS PACKAGES
                      PBULK_PACKAGES PKG_DBDIR PKGSRCDIR SANDBOX_CONFFILE
                      SYSCONFDIR UPDATE_SOURCES VARBASE"


# Paths to installed files.
#
# Can be overriden for test purposes only.
: ${PKG_COMP_ETCDIR="__PKG_COMP_ETCDIR__"}
: ${PKG_COMP_SHAREDIR="__PKG_COMP_SHAREDIR__"}
: ${SANDBOXCTL="__SANDBOXCTL__"}


# Sets defaults for configuration variables and hooks that need to exist.
#
# This function should be before the configuration file has been loaded.  This
# means that the user can undefine a required configuration variable, but we let
# him shoot himself in the foot if he so desires.
pkg_comp_set_defaults() {
    # Please remember to update pkg_comp.conf(5) if you change any default
    # values.
    shtk_config_set CVS_ROOT ":ext:anoncvs@anoncvs.NetBSD.org:/cvsroot"
    shtk_config_set DISTDIR "/usr/pkgsrc/distfiles"
    shtk_config_set FETCH_VCS "cvs"
    shtk_config_set GIT_BRANCH "trunk"
    shtk_config_set GIT_URL "https://github.com/jsonn/pkgsrc.git"
    shtk_config_set LOCALBASE "/usr/pkg"
    shtk_config_set NJOBS "$(shtk_hw_ncpus)"
    shtk_config_set PACKAGES "/usr/pkgsrc/packages"
    shtk_config_set PBULK_PACKAGES "/usr/pkgsrc/packages/pbulk"
    shtk_config_set PKG_DBDIR "/usr/pkg/libdata/pkgdb"
    shtk_config_set PKGSRCDIR "/usr/pkgsrc"
    shtk_config_set SYSCONFDIR "/etc"
    shtk_config_set UPDATE_SOURCES "true"
    shtk_config_set VARBASE "/var"

    post_fetch_hook() { true; }
}


# Executes sandboxctl based on the pkg_comp configuration.
#
# \params ... The options and arguments to forward to sandboxctl.
#
# \return The exit code of sandboxctl.
run_sandboxctl() {
    # Generate a temporary configuration file for sandboxctl that stitches
    # together our default hooks and the user-provided configuration.
    #
    # Note: it feels tempting to mix together the contents of pkg_comp.conf
    # and sandboxctl.conf into the same file because their variables are
    # disjoint.  However, doing so is extremely confusing due to the way
    # shtk_config works: for example, not all global variables would be visible
    # in all hooks, and the -o flag would not be able to override sandbox.conf
    # settings.  Therefore, while it feels uglier to keep things separate, it
    # will avoid confusion down the road.
    if [ -z "${_PKG_COMP_SANDBOXCTL_CONFIG_FILE}" ]; then
        local userconf=
        if shtk_config_has SANDBOX_CONFFILE; then
            userconf="$(shtk_config_get SANDBOX_CONFFILE)"
            [ -e "${userconf}" ] || shtk_cli_error "sandbox configuration" \
                 "file ${userconf} does not exist"
        fi

        local pattern="${TMPDIR:-/tmp}/pkg_comp.XXXXXX"
        _PKG_COMP_SANDBOXCTL_CONFIG_FILE="$(mktemp "${pattern}" 2>/dev/null)"
        remove_conffile() {
            rm -f "${_PKG_COMP_SANDBOXCTL_CONFIG_FILE}"
        }
        shtk_cleanup_register remove_conffile

        {
            cat "${PKG_COMP_SHAREDIR}/sandbox.conf.pre"
            cat <<EOF
DISTDIR="$(shtk_config_has DISTDIR && shtk_config_get DISTDIR)"
PACKAGES="$(shtk_config_has PACKAGES && shtk_config_get PACKAGES)"
PBULK_PACKAGES="$(shtk_config_has PBULK_PACKAGES \
    && shtk_config_get PBULK_PACKAGES)"
PKGSRCDIR="$(shtk_config_has PKGSRCDIR && shtk_config_get PKGSRCDIR)"
EOF
            [ -z "${userconf}" ] || cat "${userconf}"
            cat "${PKG_COMP_SHAREDIR}/sandbox.conf.post"
        } >>"${_PKG_COMP_SANDBOXCTL_CONFIG_FILE}" \
            || shtk_cli_error "Failed to create sandbox.conf file"
    fi

    local vflag=
    if shtk_cli_log_level debug; then
        vflag=-v
    fi

    "${SANDBOXCTL}" -c"${_PKG_COMP_SANDBOXCTL_CONFIG_FILE}" ${vflag} "${@}"
}


# Configures the bootstrap kit, either from a prebuilt binary or from sources.
#
# Does nothing if the bootstrap kit has already been configured.
#
# \param basename Unique name for the pkg tree being configured.
# \param root Path to the root of the sandbox.
# \param packages Value of PACKAGES for this bootstrap kit.
# \param pkgdbdir Value of PKG_DBDIR for this bootstrap kit.
# \param prefix Value of PREFIX for this bootstrap kit.
# \param sysconfdir Value of SYSCONFDIR for this bootstrap kit.
# \param varbase Value of VARBASE for this bootstrap kit.
setup_bootstrap() {
    local basename="${1}"; shift
    local root="${1}"; shift
    local packages="${1}"; shift
    local pkgdbdir="${1}"; shift
    local prefix="${1}"; shift
    local sysconfdir="${1}"; shift
    local varbase="${1}"; shift

    [ ! -f "${root}${prefix}/sbin/pkg_admin" ] || return 0

    local binarykit="${packages}/bootstrap.tgz"
    if [ -e "${binarykit}" ]; then
        shtk_cli_info "Setting up bootstrap in ${prefix} using binary kit"
        run_sandboxctl run /bin/sh -c \
            "cd / && tar xzpf /pkg_comp/packages/${basename}/bootstrap.tgz" \
            || exit
    else
        mkdir -p "${root}/pkg_comp/work"
        echo ".sinclude \"/pkg_comp/${basename}.mk.conf\"" \
             >"${root}/pkg_comp/work/mk.conf.fragment"

        # Wipe any previous bootstrap work directory.  This is helpful in
        # case a bootstrap execution failed for reasons unknown to us and
        # the user wants to retry without recreating the sandbox from scratch.
        rm -rf "${root}/pkg_comp/work/${basename}/bootstrap"

        local bootstrap_sh=/bin/sh
        local dash_echo_test="$("${bootstrap_sh}" -c 'echo "\\100"')"
        if [ "$(uname -s)" != GNUkFreeBSD -a "${dash_echo_test}" = @ ]; then
            local bash
            bash="$(which bash)"
            if [ ${?} -eq 0 ]; then
                bootstrap_sh="${bash}"
            else
                shtk_cli_warning "/bin/sh appears to be dash and bash was not" \
                    "found; bootstrap will probably fail"
            fi
        fi

        shtk_cli_info "Setting up bootstrap in ${prefix} from scratch"
        run_sandboxctl run /bin/sh -c \
            "cd /pkg_comp/pkgsrc/bootstrap && env \
                 DISTDIR=/pkg_comp/distfiles \
                 PACKAGES='/pkg_comp/packages/${basename}' \
                 SH='${bootstrap_sh}' \
                 ./bootstrap \
                 --gzip-binary-kit=/pkg_comp/packages/${basename}/bootstrap.tgz\
                 --make-jobs='$(shtk_config_get NJOBS)' \
                 --mk-fragment='/pkg_comp/work/mk.conf.fragment' \
                 --pkgdbdir='${pkgdbdir}' \
                 --prefix='${prefix}' \
                 --sysconfdir='${sysconfdir}' \
                 --varbase='${varbase}' \
                 --workdir=/pkg_comp/work/${basename}/bootstrap" \
            || exit
    fi
}


# Configures bmake within the sandbox.
#
# Creates a mk.conf file with pkg_comp-specific details, and also creates a
# convenience symlink in a fixed location for interactive uses of make.
#
# Does nothing if bmake has already been configured.
#
# \param basename Unique name for the pkg tree being configured.
# \param root Path to the root of the sandbox.
# \param sysconfdir Value of SYSCONFDIR for this bootstrap kit.
setup_make() {
    local basename="${1}"; shift
    local root="${1}"; shift
    local sysconfdir="${1}"; shift

    local mk_conf="/pkg_comp/${basename}.mk.conf"
    local symlink="/pkg_comp/make-${basename}"
    [ ! -e "${root}${mk_conf}" -o ! -e "${root}${symlink}" ] || return 0

    shtk_cli_info "Setting up ${mk_conf}"
    cat >"${root}${mk_conf}" <<EOF
DISTDIR=/pkg_comp/distfiles
PACKAGES=/pkg_comp/packages/${basename}
PKGSRCDIR=/pkg_comp/pkgsrc
WRKOBJDIR=/pkg_comp/work/${basename}

BINPKG_SITES=
DEPENDS_TARGET=bin-install

MAKE_JOBS=$(shtk_config_get NJOBS)
EOF

    ln -s "${prefix}/bin/bmake" "${root}${symlink}"
}


# Configures pkg_install within the sandbox.
#
# Creates a pkg_install.conf file with pkg_comp-specific details.
#
# Does nothing if pkg_install has already been configured.
#
# \param basename Unique name for the pkg tree being configured.
# \param root Path to the root of the sandbox.
# \param sysconfdir Value of SYSCONFDIR for this bootstrap kit.
# \param pkgdbdir Value of PKG_DBDIR for this bootstrap kit.
setup_pkginstall() {
    local basename="${1}"; shift
    local root="${1}"; shift
    local sysconfdir="${1}"; shift
    local pkgdbdir="${1}"; shift

    local pkginstall_conf="${sysconfdir}/pkg_install.conf"
    [ ! -e "${root}${pkginstall_conf}" ] || return 0

    shtk_cli_info "Setting up ${pkginstall_conf}"
    cat >"${root}${pkginstall_conf}" <<EOF
PKG_DBDIR=${pkgdbdir}
PKG_PATH=/pkg_comp/packages/${basename}/All
EOF
}


# Sets up a pkg installation, including bootstrap, bmake, and pkg_install.
#
# This is idempotent: once the installation has been configured, this function
# does nothing.  This is good for speed, but can lead to inconsistencies if the
# user changes the configuration without rebuilding the sandbox.
#
# \param basename Unique name for the pkg tree being configured.
# \param root Path to the root of the sandbox.
# \param packages Value of PACKAGES for this bootstrap kit.
# \param pkgdbdir Value of PKG_DBDIR for this bootstrap kit.
# \param prefix Value of PREFIX for this bootstrap kit.
# \param sysconfdir Value of SYSCONFDIR for this bootstrap kit.
# \param varbase Value of VARBASE for this bootstrap kit.
full_bootstrap() {
    local basename="${1}"; shift
    local root="${1}"; shift
    local packages="${1}"; shift
    local pkgdbdir="${1}"; shift
    local prefix="${1}"; shift
    local sysconfdir="${1}"; shift
    local varbase="${1}"; shift

    setup_bootstrap "${basename}" "${root}" "${packages}" "${pkgdbdir}" \
        "${prefix}" "${sysconfdir}" "${varbase}"
    setup_make "${basename}" "${root}" "${sysconfdir}"
    setup_pkginstall "${basename}" "${root}" "${sysconfdir}" "${pkgdbdir}"
}


# Sets up a pkg installation in the location configured by the user.
#
# \param root Path to the root of the sandbox.
bootstrap_pkg() {
    local root="${1}"; shift

    full_bootstrap \
        "pkg" \
        "${root}" \
        "$(shtk_config_get PACKAGES)" \
        "$(shtk_config_get PKG_DBDIR)" \
        "$(shtk_config_get LOCALBASE)" \
        "$(shtk_config_get SYSCONFDIR)" \
        "$(shtk_config_get VARBASE)" || exit

    if shtk_config_has EXTRA_MKCONF; then
        local extra_mkconf="$(shtk_config_get EXTRA_MKCONF)"
        cat "$(shtk_config_get EXTRA_MKCONF)" >>"${root}/pkg_comp/pkg.mk.conf" \
            || shtk_cli_error "Failed to append ${extra_mkconf} to mk.conf"
    fi
}


# Sets up a pkg installation for pbulk and also configures pbulk.
#
# \param root Path to the root of the sandbox.
bootstrap_pbulk() {
    local root="${1}"; shift

    full_bootstrap \
        "pbulk" \
        "${root}" \
        "$(shtk_config_get PBULK_PACKAGES)" \
        "/pkg_comp/pbulk/libdata/pkgdb" \
        "/pkg_comp/pbulk" \
        "/pkg_comp/pbulk/etc" \
        "/pkg_comp/pbulk/var" || exit

    cat >>"${root}/pkg_comp/pbulk.mk.conf" <<EOF
# Be permissive of warnings raised during the build of our own infrastructure.
# Linux is especially picky and it's easy to trip over different warnings on
# different platforms.  We just don't want to abort the bootstrapping process
# for such a lame reason.
BUILDLINK_TRANSFORM+=rm:-Werror
EOF

    run_sandboxctl run /bin/sh -c \
        "cd /pkg_comp/pkgsrc/pkgtools/pbulk && \
         /pkg_comp/pbulk/bin/bmake bin-install" || exit
    # bin-install implies clean when building from source, so no need to do that
    # on our own.

    # Make sure pbulk.conf exists in the etc directory in case automatic
    # installation of configuration files is disabled.
    local pbulk_conf="${root}/pkg_comp/pbulk/etc/pbulk.conf"
    cp "${root}/pkg_comp/pbulk/share/examples/pbulk/pbulk.conf" "${pbulk_conf}"

    # Replaces the value of a single variable in pbulk.conf.
    #
    # This is inefficient and possibly fragile, but we cannot just append
    # overrides to the end of the file because some variables are derived from
    # others.
    pbulk_set() {
        local var="${1}"; shift
        local value="${1}"; shift

        if grep "^${var}=" "${pbulk_conf}" >/dev/null; then
            sed "/^${var}=/s,^.*$,${var}='${value}'," "${pbulk_conf}" \
                >"${pbulk_conf}.new"
            mv "${pbulk_conf}.new" "${pbulk_conf}"
        else
            echo "${var}=${value}" >>"${pbulk_conf}"
        fi
    }

    pbulk_set checksum_packages no
    pbulk_set mail true
    pbulk_set master_mode no
    pbulk_set rsync true
    pbulk_set unprivileged_user root

    # Configure pbulk's file layout.
    pbulk_set bulklog /pkg_comp/work/bulklog
    pbulk_set limited_list /pkg_comp/pbulk/etc/pbulk.list
    pbulk_set loc /pkg_comp/work/bulklog/meta

    # Configure pkgsrc's file layout.
    pbulk_set bootstrapkit "/pkg_comp/packages/pkg/bootstrap.tgz"
    pbulk_set packages "/pkg_comp/packages/pkg"
    pbulk_set pkgdb "$(shtk_config_get PKG_DBDIR)"
    pbulk_set pkgsrc /pkg_comp/pkgsrc
    pbulk_set prefix "$(shtk_config_get LOCALBASE)"
    pbulk_set varbase "$(shtk_config_get VARBASE)"
}


# Generates pkg_summary for all built packages.
#
# pbulk does this on its own, but it only adds the packages that have just been
# built to pkg_summary.  For pkg_comp, because we want to support the case where
# users request individual additional packages to be built, we have to
# regenerate pkg_summary using *all* existing binary packages and not only those
# that were handled by pbulk.
#
# \param root Path to the root of the sandbox.
generate_pkg_summary() {
    local root="${1}"; shift

    shtk_cli_info "Generating pkg_summary"
    # We need to run this within the sandbox because we have to execute pbulk's
    # copy of pkg_info.
    cat >"${root}/tmp/pkg_summary.sh" <<EOF
#! /bin/sh
cd /pkg_comp/packages/pkg/All
rm -f pkg_summary.*
ls -1 *.tgz | xargs /pkg_comp/pbulk/sbin/pkg_info -X | gzip -c >pkg_summary.gz
gzip -dc <pkg_summary.gz | bzip2 -c >pkg_summary.bz2
EOF
    chmod +x "${root}/tmp/pkg_summary.sh"
    run_sandboxctl run /tmp/pkg_summary.sh
}


# Automatic mode.
#
# Updates the pkgsrc tree, creates a sandbox, bootstraps pkgsrc, builds a set of
# packages, and tears the sandbox down.
#
# \params ... The options and arguments to the command.
pkg_comp_auto() {
    local OPTIND  # Cope with bash failing to reinitialize getopt.
    while getopts ':f' arg "${@}"; do
        case "${arg}" in
            f)  # Convenience flag for a "fast mode".
                shtk_config_set "UPDATE_SOURCES" "false"
                ;;

            \?)
                shtk_cli_usage_error "Unknown option -${OPTARG} in build"
                ;;
        esac
    done
    shift $((${OPTIND} - 1))

    if [ ${#} -eq 0 ]; then
        if shtk_config_has AUTO_PACKAGES; then
            set -- $(shtk_config_get AUTO_PACKAGES)
        fi
    fi
    [ ${#} -gt 0 ] || shtk_cli_usage_error "auto requires at least one" \
        "package name as an argument or in the AUTO_PACKAGES variable"

    if shtk_config_get_bool UPDATE_SOURCES; then
        pkg_comp_fetch
    fi

    # We must validate packages after invoking pkg_comp_fetch to ensure the
    # pkgsrc tree exists.
    local packages
    packages="$(pkgsrc_expand_packages "$(shtk_config_get PKGSRCDIR)" "${@}")" \
        || shtk_cli_error "Some packages do not exist in pkgsrc; please fix" \
            "and retry"

    local root
    root="$(run_sandboxctl config SANDBOX_ROOT)" || exit

    if [ -d "${root}/pkg_comp" ]; then
        shtk_cli_warning "Reusing existing sandbox; if this is not what you" \
            "want to do, abort now with Ctrl-C and use sandbox-delete to" \
            "wipe the previous sandbox"
    else
        cleanup() {
            shtk_cli_info "Destroying sandbox"
            run_sandboxctl destroy
        }
        shtk_cleanup_register cleanup

        shtk_cli_info "Creating sandbox"
        run_sandboxctl create || exit
    fi

    pkg_comp_build ${packages} || exit
}


# Bootstraps pkgsrc on the user's configured location and for pbulk.
pkg_comp_bootstrap() {
    [ ${#} -eq 0 ] \
        || shtk_cli_usage_error "bootstrap does not take any arguments"

    local root
    root="$(run_sandboxctl config SANDBOX_ROOT)" || exit

    [ ! -e "${root}/pkg_comp/done.bootstrap" ] || return 0
    shtk_cli_info "Bootstrapping pkg tools"
    bootstrap_pkg "${root}" || exit
    shtk_cli_info "Bootstrapping pbulk tools"
    bootstrap_pbulk "${root}" || exit
    touch "${root}/pkg_comp/done.bootstrap"
}


# Builds one or more packages in an already-existing sandbox.
#
# \params ... The options and arguments to the command.
pkg_comp_build() {
    [ ${#} -gt 0 ] \
        || shtk_cli_usage_error "build requires at least one package name"

    local packages
    packages="$(pkgsrc_expand_packages "$(shtk_config_get PKGSRCDIR)" "${@}")" \
        || shtk_cli_error "Some packages do not exist in pkgsrc; please fix" \
            "and retry"

    pkg_comp_bootstrap || exit

    local root
    root="$(run_sandboxctl config SANDBOX_ROOT)" || exit

    shtk_cli_info "Adding packages to be built to pbulk.list"
    local list="${root}/pkg_comp/pbulk/etc/pbulk.list"
    rm -f "${list}"
    for package in ${packages}; do
        echo "${package}" >>"${list}"
    done

    # Removing bulklog/success seems to be necessary to restart a build, as
    # otherwise bulkbuild does not build modified packages.  Is this correct?
    rm -f "${root}/pkg_comp/work/bulklog/success"
    shtk_cli_info "Starting pbulk build in the sandbox"
    run_sandboxctl run /pkg_comp/pbulk/bin/bulkbuild || \
        shtk_cli_error "bulkbuild failed; see ${root}/pkg_comp/work/bulklog/" \
            "for possible details"
    generate_pkg_summary "${root}"
}


# Dumps the loaded configuration.
pkg_comp_config() {
    [ ${#} -eq 0 ] || shtk_cli_usage_error "config does not take any arguments"

    for var in ${PKG_COMP_CONFIG_VARS}; do
        if shtk_config_has "${var}"; then
            echo "${var} = $(shtk_config_get "${var}")"
        else
            echo "${var} is undefined"
        fi
    done

    echo
    run_sandboxctl config || exit
}


# Fetches a copy of the pkgsrc tree, or updates an existing one.
pkg_comp_fetch() {
    [ ${#} -eq 0 ] || shtk_cli_usage_error "fetch does not take any arguments"

    shtk_cli_info "Updating pkgsrc tree"

    case "$(shtk_config_get FETCH_VCS)" in
        cvs)
            shtk_cvs_fetch "$(shtk_config_get CVS_ROOT)" pkgsrc \
                "$(shtk_config_get_default CVS_TAG '')" \
                "$(shtk_config_get PKGSRCDIR)"
            ;;

        git)
            git_fetch "$(shtk_config_get GIT_URL)" \
                "$(shtk_config_get GIT_BRANCH)" \
                "$(shtk_config_get PKGSRCDIR)"
            ;;

        *)
            shtk_cli_error "Unknown VCS name in FETCH_VCS; found" \
                "$(shtk_config_get FETCH_VCS)"
            ;;
    esac

    shtk_config_run_hook post_fetch_hook
}


# Loads the configuration file specified in the command line.
#
# \param config_name Name of the desired configuration.  It can be either a
#     configuration name (no slashes) or a path.
pkg_comp_config_load() {
    local config_name="${1}"; shift

    local config_file=
    case "${config_name}" in
        */*|*.conf)
            config_file="${config_name}"
            ;;

        *)
            config_file="${PKG_COMP_ETCDIR}/${config_name}.conf"
            [ -e "${config_file}" ] \
                || shtk_cli_usage_error "Cannot locate configuration named" \
                "'${config_name}'"
            ;;
    esac
    shtk_config_load "${config_file}"
}


# Entry point to the program.
#
# \param ... Command-line arguments to be processed.
#
# \return An exit code to be returned to the user.
main() {
    local config_name="default"

    shtk_config_init ${PKG_COMP_CONFIG_VARS}

    local OPTIND
    while getopts ':c:o:v' arg "${@}"; do
        case "${arg}" in
            c)  # Name of the configuration to load.
                config_name="${OPTARG}"
                ;;

            o)  # Override for a particular configuration variable.
                shtk_config_override "${OPTARG}"
                ;;

            v)  # Be verbose.
                shtk_cli_set_log_level debug
                ;;

            \?)
                shtk_cli_usage_error "Unknown option -${OPTARG}"
                ;;
        esac
    done
    shift $((${OPTIND} - 1))
    OPTIND=1  # Should not be necessary due to the 'local' above.

    [ ${#} -ge 1 ] || shtk_cli_usage_error "No command specified"

    local exit_code=0

    local command="${1}"; shift
    case "${command}" in
        auto|bootstrap|build|config|fetch)
            pkg_comp_set_defaults
            pkg_comp_config_load "${config_name}"
            "pkg_comp_${command}" "${@}" || exit_code="${?}"
            ;;

        sandbox-*)
            pkg_comp_set_defaults
            pkg_comp_config_load "${config_name}"
            local subcommand="$(echo "${command}" | cut -d - -f 2-)"
            run_sandboxctl "${subcommand}" "${@}" || exit_code="${?}"
            ;;

        *)
            shtk_cli_usage_error "Unknown command ${command}"
            ;;
    esac

    return "${exit_code}"
}
