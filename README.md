# Welcome to pkg_comp, the pkgsrc compiler!

[pkgsrc](http://pkgsrc.org) is a framework for building third-party
software on a multitude of platforms, including (but not limited to):
FreeBSD, Linux, macOS, and NetBSD.

**pkg_comp is a tool for building and maintaining a repository of binary
pkgsrc packages.** pkg_comp does this by building the packages in a clean
and self-contained environment, hiding all complexity behind a simple
command and configuration file.  pkg_comp makes it even possible to
automate the builds of packages from cron so that you always have an
up-to-date local repository.

pkg_comp orchestrates VCS tools such as CVS and Git to **fetch the initial
pkgsrc tree** and to keep it up to date; the **creation of a fresh
sandbox** to build packages in; the **pkgsrc bootstrapping process**; and
the **use of the pbulk infrastructure** to build the desired set of
packages in an optimal manner.

With pkg_comp, you can quickly and effortlessly get third-party software up
and running, and you can target both your own machine or other machines
with different configurations.  As you build the packages from source,
pkgsrc puts you in control by letting you tune the software to your needs.

pkg_comp is licensed under a **[liberal BSD 3-clause license](COPYING)**.
This is not an official Google product.

## Download and installation

The latest version is **[pkg_comp 2.1](../../releases/tag/pkg_comp-2.1)**
and was released on January 14th, 2019.

**Read the [installation instructions](INSTALL.md)** for details on which
file to download and how to get started.

**Read the [release notes](NEWS)** for information about the changes in
this and all previous releases.

## Contributing

Want to contribute?  Great!  But please first read the guidelines provided
in [CONTRIBUTING.md](CONTRIBUTING.md).

If you are curious about who made this project possible, you can check out
the [list of copyright holders](AUTHORS) and the [list of
individuals](CONTRIBUTORS).

## Support

Please use the [bug tracker](https://github.com/jmmv/pkg_comp/issues) for
any support inquiries.

*Homepage:* https://github.com/jmmv/pkg_comp/
