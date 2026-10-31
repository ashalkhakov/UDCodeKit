#
# SQL.bundle on GNUstep: UDCode's databases (see Sources/UDSQLPlugin.h), in
# UDCode.app's PlugIns. SQLite is linked; libpq and libmariadb (or
# libmysqlclient) are built against (their headers) and loaded when a
# connection needs them, so neither is needed to run it. Its ER diagrams are
# DiagramKit's (.github/pins.env's DIAGRAMKIT_VERSION, installed with the
# GNUstep stack). Its references to UDCodeKit, LSPKit and
# UDPieceTable are left for the application to resolve when it loads the
# bundle (on Windows a DLL is linked against them: UD_PLUGIN_LIBS).
#
BUNDLE_NAME = SQL
BUNDLE_EXTENSION = .bundle

include ../../scripts/gnustep.make
include $(GNUSTEP_MAKEFILES)/common.make

SQL_OBJC_FILES = $(wildcard Sources/*.m)
SQL_PRINCIPAL_CLASS = UDSQLPlugin
# its navigator, sheets and results: AppKit's
SQL_NEEDS_GUI = yes
SQL_RESOURCE_FILES = Resources/LanguageInfo.plist $(wildcard Resources/*.xib)
SQL_INCLUDE_DIRS = -I$(UD_INCLUDE) -I$(UD_INCLUDE)/UDCodeKit -ISources
# libpq's and MariaDB Connector/C's headers (pg_config, mariadb_config: the
# packages' own; Debian's places as a fallback): the libraries are loaded, not
# linked. Without them it builds, and says it can't reach those databases.
SQL_INCLUDE_DIRS += $(addprefix -I,$(shell pg_config --includedir 2>/dev/null)) \
    $(shell mariadb_config --include 2>/dev/null || mysql_config --include 2>/dev/null) \
    -I/usr/include/postgresql -I/usr/include/mariadb
SQL_STANDARD_INSTALL = no
SQL_BUNDLE_LIBS += $(UD_PLUGIN_LIBS) -lDiagramKitUI -lDiagramKit -lsqlite3 $(if $(UD_WINDOWS),,-ldl)

include $(GNUSTEP_MAKEFILES)/bundle.make
