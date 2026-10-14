#
# UDCode and UDCodeKit on GNUstep: the frameworks (UDPieceTable, LSPKit,
# UDCodeKit), the grammar bundles, the application and the tests. Built
# out of the tree, under build/gnustep/ (scripts/gnustep.make).
#
#   make          everything
#   make check    the tests (under Xvfb when there is no display): the text
#                 model's, then the editor's, which drive its windows
#
ifeq ($(GNUSTEP_MAKEFILES),)
  $(error Set GNUSTEP_MAKEFILES (source GNUstep.sh).)
endif

include $(GNUSTEP_MAKEFILES)/common.make

PACKAGE_NAME = UDCode
UD_GRAMMAR_DIRS = $(patsubst %/GNUmakefile,%,$(wildcard tree-sitter-*/GNUmakefile))
SUBPROJECTS = UDPieceTable LSPKit UDCodeKit $(UD_GRAMMAR_DIRS) Sources \
              UDPieceTable/Tests Tests

include $(GNUSTEP_MAKEFILES)/aggregate.make

# A screen wider than the windows the tests size (xvfb-run's is 1280 wide,
# and a window is kept to its screen).
XVFB = $(if $(DISPLAY),,$(shell command -v xvfb-run >/dev/null 2>&1 && echo "xvfb-run -a -s '-screen 0 1920x1200x24'"))
check::
	$(MAKE) -C UDPieceTable/Tests run-tests
	$(XVFB) $(MAKE) -C Tests run-tests
