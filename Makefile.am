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

PHONY_TARGETS =

doc_DATA = AUTHORS CONTRIBUTING.md CONTRIBUTORS COPYING NEWS
noinst_DATA = INSTALL README
EXTRA_DIST = $(doc_DATA) INSTALL README

BUILD_SED = \
	sed -e 's,__ATF_SH__,$(ATF_SH),g' \
	    -e 's,__PKG_COMP_BASESYSCONFDIR__,$(sysconfdir),g' \
	    -e 's,__PKG_COMP_BINDIR__,$(exec_prefix)/sbin,g' \
	    -e 's,__PKG_COMP_DOCDIR__,$(docdir),g' \
	    -e 's,__PKG_COMP_ETCDIR__,$(pkg_comp_confdir),g' \
	    -e 's,__PKG_COMP_SHAREDIR__,$(pkgdatadir),g' \
	    -e 's,__SANDBOXCTL__,$(SANDBOXCTL),g'
BUILD_SCRIPT = \
	$(BUILD_SED) <"$(srcdir)/$${source}" | \
	    $(SHTK_TOOL) build -o "$${target}" -
BUILD_FILE = \
	$(BUILD_SED) <"$(srcdir)/$${source}" >"$${target}.tmp"; \
	mv "$${target}.tmp" "$${target}"
BUILD_OLD_TEST = \
	$(BUILD_FILE); \
	chmod +x "$${target}"
BUILD_TEST = \
	$(BUILD_SED) <"$(srcdir)/$${source}" | \
	    $(SHTK_TOOL) build -m shtk_unittest_main -o "$${target}" -

sbin_SCRIPTS = pkg_comp
CLEANFILES = pkg_comp
EXTRA_DIST += pkg_comp.sh
pkg_comp: $(srcdir)/pkg_comp.sh
	$(AM_V_GEN)source=pkg_comp.sh target=pkg_comp; $(BUILD_SCRIPT)

sbin_SCRIPTS += pkg_comp4cron
CLEANFILES += pkg_comp4cron
EXTRA_DIST += pkg_comp4cron.sh
pkg_comp4cron: $(srcdir)/pkg_comp4cron.sh
	$(AM_V_GEN)source=pkg_comp4cron.sh target=pkg_comp4cron; $(BUILD_SCRIPT)

man_MANS = pkg_comp.8
CLEANFILES += pkg_comp.8
EXTRA_DIST += pkg_comp.8.in
pkg_comp.8: $(srcdir)/pkg_comp.8.in
	$(AM_V_GEN)source=pkg_comp.8.in target=pkg_comp.8; $(BUILD_FILE)

dist_man_MANS  = pkg_comp.conf.5
dist_man_MANS += pkg_comp4cron.8

dist_pkg_comp_conf_DATA = extra.mk.conf

nodist_pkg_comp_conf_DATA = default.conf
CLEANFILES += default.conf
EXTRA_DIST += default.conf.in
default.conf: $(srcdir)/default.conf.in
	$(AM_V_GEN)source=default.conf.in target=default.conf; $(BUILD_FILE)

nodist_pkg_comp_conf_DATA += sandbox.conf
CLEANFILES += sandbox.conf
EXTRA_DIST += sandbox.conf.in
sandbox.conf: $(srcdir)/sandbox.conf.in
	$(AM_V_GEN)source=sandbox.conf.in target=sandbox.conf; $(BUILD_FILE)

dist_pkgdata_DATA = sandbox.conf.pre sandbox.conf.post

shtk_modulesdir = $(SHTK_MODULESDIR)
dist_shtk_modules_DATA  = pkg_comp_git.subr
dist_shtk_modules_DATA += pkg_comp_pkgsrc.subr

if WITH_ATF
dist_pkgtests_DATA = Kyuafile

pkgtests_SCRIPTS = pkg_comp_git_test
CLEANFILES += pkg_comp_git_test
EXTRA_DIST += pkg_comp_git_test.sh
pkg_comp_git_test: $(srcdir)/pkg_comp_git_test.sh
	$(AM_V_GEN)source="$(srcdir)/pkg_comp_git_test.sh" \
	target=pkg_comp_git_test; \
	$(BUILD_TEST)

pkgtests_SCRIPTS += pkg_comp_pkgsrc_test
CLEANFILES += pkg_comp_pkgsrc_test
EXTRA_DIST += pkg_comp_pkgsrc_test.sh
pkg_comp_pkgsrc_test: $(srcdir)/pkg_comp_pkgsrc_test.sh
	$(AM_V_GEN)source="$(srcdir)/pkg_comp_pkgsrc_test.sh" \
	target=pkg_comp_pkgsrc_test; \
	$(BUILD_TEST)

pkgtests_SCRIPTS += pkg_comp_test
CLEANFILES += pkg_comp_test
EXTRA_DIST += pkg_comp_test.sh
pkg_comp_test: $(srcdir)/pkg_comp_test.sh
	$(AM_V_GEN)source=pkg_comp_test.sh target=pkg_comp_test; \
	$(BUILD_OLD_TEST)

pkgtests_SCRIPTS += pkg_comp_inttest
CLEANFILES += pkg_comp_inttest
EXTRA_DIST += pkg_comp_inttest.sh
pkg_comp_inttest: $(srcdir)/pkg_comp_inttest.sh
	$(AM_V_GEN)source=pkg_comp_inttest.sh target=pkg_comp_inttest; \
	$(BUILD_OLD_TEST)

pkgtests_SCRIPTS += pkg_comp4cron_test
CLEANFILES += pkg_comp4cron_test
EXTRA_DIST += pkg_comp4cron_test.sh
pkg_comp4cron_test: $(srcdir)/pkg_comp4cron_test.sh
	$(AM_V_GEN)source=pkg_comp4cron_test.sh target=pkg_comp4cron_test; \
	$(BUILD_TEST)

if HAVE_KYUA
CHECK_ENVIRONMENT  = PATH=$(abs_top_builddir):$${PATH}
CHECK_ENVIRONMENT += PKG_COMP_ETCDIR=$(abs_top_srcdir)
CHECK_ENVIRONMENT += PKG_COMP_SHAREDIR=$(abs_top_srcdir)
CHECK_ENVIRONMENT += SHTK_MODULESPATH=$(abs_top_srcdir):$${SHTK_MODULESPATH}
INSTALLCHECK_ENVIRONMENT = PATH=$(prefix)/sbin:$${PATH}

check-local: check-kyua
PHONY_TARGETS += check-kyua
check-kyua:
	$(CHECK_ENVIRONMENT) $(TESTS_ENVIRONMENT) \
	    $(KYUA) test \
	    --kyuafile='$(top_srcdir)/Kyuafile' --build-root='$(top_builddir)'

installcheck-local: installcheck-kyua
PHONY_TARGETS += installcheck-kyua
installcheck-kyua:
	cd $(pkgtestsdir) && $(INSTALLCHECK_ENVIRONMENT) $(TESTS_ENVIRONMENT) \
	    $(KYUA) test
else  # HAVE_KYUA
PHONY_TARGETS += missing-kyua
missing-kyua:
	@echo "WARNING: kyua not found; no tests run"

check-local: missing-kyua
installcheck-local: missing-kyua
endif  # HAVE_KYUA
else  # WITH_ATF
dist-hook: forbid-dist
PHONY_TARGETS += forbid-dist
forbid-dist:
	@echo "Sorry; cannot make dist without atf."
	@false
endif  # WITH_ATF

PHONY_TARGETS += clean-all
clean-all:
	GIT="$(GIT)" $(SH) $(srcdir)/admin/clean-all.sh

.PHONY: $(PHONY_TARGETS)
