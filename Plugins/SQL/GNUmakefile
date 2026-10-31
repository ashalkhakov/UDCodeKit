#
# SQL.bundle on GNUstep: UDCode's databases (see Sources/UDSQLPlugin.h), in
# UDCode.app's PlugIns. SQLite is linked; libpq and libmariadb (or
# libmysqlclient) are loaded when a connection needs them, so neither is
# needed to build or run it. Its references to UDCodeKit, LSPKit and
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
SQL_STANDARD_INSTALL = no
SQL_BUNDLE_LIBS += $(UD_PLUGIN_LIBS) -lsqlite3 $(if $(UD_WINDOWS),,-ldl)

include $(GNUSTEP_MAKEFILES)/bundle.make
