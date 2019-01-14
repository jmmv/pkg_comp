# Installation instructions

Getting pkg_comp up and running is easy, and the process does not require a
pre-existing pkgsrc installation.  This is intentional given that pkg_comp
is intended to simplify interactions with pkgsrc, so cyclic dependencies would
be suboptimal.

You can choose to use an installer package, the installer script, source or
binary packages for your operating system, or to build from source.

## Using the generic installer

**Run:**

    curl -L https://raw.githubusercontent.com/jmmv/pkg_comp/master/admin/bootstrap.sh | /bin/sh /dev/stdin

This will fetch and run a script that downloads pkg_comp and its dependencies as
source packages, builds all of them, and installs the results under the
`/usr/local/` prefix.  The resulting installation is barebones: i.e. the
packages are installed exactly as distributed by the upstream distribution
files.  No post-install configuration is executed, which means you will have to
set everything up by yourself; see `pkg_comp(8)` to get started.

You will need the `pkg-config` tool on your system for this to work, but
that should be the only necessary dependency.

## Using the macOS installer

**Download and run the
[pkg_comp-2.1-20190114-macos.pkg](../../releases/download/pkg_comp-2.1/pkg_comp-2.1-20190114-macos.pkg)
installer.**  As a prerequisite on macOS, you will also have to **[download
and install OSXFUSE 3](https://osxfuse.github.io/).**

**Read
[Easy pkgsrc on macOS with pkg_comp 2.0](http://julio.meroh.net/2017/02/pkg_comp-2.0-tutorial-macos.html)
for a tutorial on this package.**

This is a highly-customized installation of pkg_comp intended to simplify the
use of pkgsrc on this platform.  Because of this, the installer is very
prescriptive about the configuration and the location of the installed files.
In particular, the package will:

*   Install pkg_comp as `/usr/local/sbin/pkg_comp`.
*   Place configuration files under `/usr/local/etc/pkg_comp/`.
*   Create `/var/pkg_comp/` to host the pkgsrc tree and the built packages.
*   Default the installation of the built packages to `/opt/pkg`.
*   Configure a daily cron job, as root, to build a fresh set of packages.

All you need to do to get started is modify
`/usr/local/etc/pkg_comp/list.txt` to indicate which packages you would
like built and they will eventually show up under
`/var/pkg_comp/packages/All/`.

You can use `/usr/local/libexec/pkg_comp/uninstall.sh` to undo the actions
performed by this package.  The contents of `/var/pkg_comp/` will be left
behind.  Feel free to destroy that directory if you do not need any of the
packages you previously built nor the pkgsrc tree.

## Using operating-system packages

The following packages are known to exist:

*   **pkgsrc** (for NetBSD): `pkgtools/pkg_comp` and `pkgtools/pkg_comp-cron`.
    *   **Read
        [Keeping NetBSD up-to-date with pkg_comp 2.0](http://julio.meroh.net/2017/02/pkg_comp-2.0-tutorial-netbsd.html)**
        for details on how to use the `pkg_comp-cron` package.

## Building from source

Download the
[pkg_comp-2.1.tar.gz](../../releases/download/pkg_comp-2.1/pkg_comp-2.1.tar.gz)
distribution file.

pkg_comp uses the GNU Automake and GNU Autoconf utilities as its build
system.  These are used only when building the package from the source
code tree.  If you want to install pkg_comp from a prebuilt package
provided by your operating system, you do not need to read this
document.

For the impatient:

    $ ./configure
    $ make
    $ make check
    Gain root privileges
    # make install
    Drop root privileges
    $ make installcheck

Or alternatively, install as a regular user into your home directory:

    $ ./configure --prefix ~/local
    $ make
    $ make check
    $ make install
    $ make installcheck

### Dependencies

To build and use pkg_comp successfully you need:

* shtk 1.7 or greater.
* sandboxctl 1.0 or greater.
* pkg-config.

Optionally, if you want to build and run the tests (recommended), you
need:

* ATF 0.17 or greater.
* Kyua 0.6 or greater.

If you are building pkg_comp from the code on the repository, you will
also need the following tools:

* GNU Autoconf.
* GNU Automake.

### Regenerating the build system

This is not necessary if you are building from a formal release
distribution file.

On the other hand, if you are building pkg_comp from code extracted
from the repository, you must first regenerate the files used by the
build system.  You will also need to do this if you modify configure.ac,
Makefile.am or any of the other build system files.  To do this, simply
run:

    $ autoreconf -i -s

If ATF and/or shtk are installed in a different prefix than Autoconf,
you will also need to tell autoreconf where the ATF and shtk M4 macros
are located.  Otherwise, the configure script will be incomplete and
will show confusing syntax errors mentioning, for example, ATF_CHECK_SH.
To fix this, you have to run autoreconf in the following manner,
replacing '<atf-prefix>' and '<shtk-prefix>' with the appropriate path:

    $ autoreconf -i -s -I <atf-prefix>/share/aclocal \
      -I <shtk-prefix>/share/aclocal

### General build procedure

To build and install the source package, you must follow these steps:

1. Configure the sources to adapt to your operating system.  This is
   done using the 'configure' script located on the sources' top
   directory, and it is usually invoked without arguments unless you
   want to change the installation prefix.  More details on this
   procedure are given on a later section.

2. Build the sources to generate the binaries and scripts.  Simply run
   'make' on the sources' top directory after configuring them.  No
   problems should arise.

3. Install the library by running 'make install'.  You may need to
   become root to issue this step.

4. Issue any manual installation steps that may be required.  These are
   described later in their own section.

5. Check that the installed library works by running 'make
   installcheck'.  You do not need to be root to do this.

### Configuration flags

The most common, standard flags given to 'configure' are:

* --prefix=directory
  Possible values: Any path
  Default: /usr/local

  Specifies where the library (scripts and all associated files) will
  be installed.

* --sysconfdir=directory
  Possible values: Any path
  Default: /usr/local/etc

  Specifies where the installed programs will look for configuration
  files.  '/pkg_comp' will be appended to the given path unless
  PKG_COMP_CONFSUBDIR is redefined as explained later on.

* --help
  Shows information about all available flags and exits immediately,
  without running any configuration tasks.

The following environment variables are specific to pkg_comp's
'configure' script:

* PKG_COMP_CONFSUBDIR
  Possible values: empty, a relative path.
  Default: pkg_comp.

  Specifies the subdirectory of the configuration directory (given by
  the --sysconfdir argument) under which pkg_comp will search for its
  configuration files.

The following flags are specific to pkg_comp's 'configure' script:

* --with-atf
  Possible values: yes, no, auto.
  Default: auto.

  Enables usage of ATF to build (and later install) the tests.

  Setting this to 'yes' causes the configure script to look for ATF
  unconditionally and abort if not found.  Setting this to 'auto' lets
  configure perform the best decision based on availability of ATF.
  Setting this to 'no' explicitly disables ATF usage.

  When support for tests is enabled, the build process will generate the
  test programs and will later install them into the tests tree.
  Running 'make check' or 'make installcheck' from within the source
  directory will cause these tests to be run with Kyua (assuming it is
  also installed).

### Run the tests!

Lastly, after a successful installation (and assuming you built the
sources with support for ATF), you should periodically run the tests
from the final location to ensure things remain stable.  Do so as
follows:

    $ kyua test -k /usr/local/tests/pkg_comp/Kyuafile

And if you see any tests fail, do not hesitate to report them in:

    https://github.com/jmmv/pkg_comp/issues/

Thank you!
