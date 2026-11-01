# Databases in UDCode

Two things most programmers do with a database every day, and nothing more:
look inside one — a Core Data store first of all — and run SQL against the
ones they already have. Administration (users, roles, backups, server
settings, query plans) is left to each database's own tools.

Xcode has no SQL, so this keeps its spirit on new ground: what a database
holds is a navigator, a query is a document like any other, and its results
are under it, as a playground's are under its code. It works as VS Code's SQL
extensions do: connections kept as settings, a document run against one of
them, its results beside it.

## Connections

The Databases navigator (the last segment, a cylinder) lists them:

- **SQLite**: a file. Double-click a `.sqlite` in the project navigator — a
  Core Data store, say — and it opens here, not as text. Nothing is ever
  created: a connection opens the file as it is.
- **PostgreSQL**: `postgresql://user@host:port/database?sslmode=…`, as libpq
  takes it.
- **MySQL and MariaDB**: `mysql://user@host:port/database`; "localhost" is
  the client library's own (its socket).

Add one with **+** at the bottom (or edit one from its menu). It is kept in
the project's `.udcode/settings.json`, under `"databases"` (a name and a URL,
to share with the folder), or in your own defaults, for every project.
**Passwords are never written to settings or a project's files.** One is
asked for when the server wants it (or given in the connection's sheet)
and, with **Remember password** ticked, kept where the system keeps
passwords: the Keychain on macOS, the Secret Service on Linux (GNOME
Keyring, KWallet: through libsecret, when it and a D-Bus session are
there), Credential Manager on Windows, under "UDCode database" and the
connection's URL. Unticked, or where the system keeps none, it is kept
until UDCode quits. A kept password that fails is asked for again;
removing a connection forgets its password.

Open a connection and its tables and views are listed, each with its
columns (type, primary and foreign keys, NOT NULL), indexes and foreign
keys. Double-click a table for its first rows.

SQLite is built in. PostgreSQL's and MySQL's client libraries come with
UDCode, so there is nothing to install: the Mac app, the AppImage and the
Windows installer (and portable zip) each carry libpq and MariaDB
Connector/C's libmariadb (which speaks to MySQL servers too, MySQL 8's
`caching_sha2_password` included), with what they link that a machine need
not have:

| | Where | What |
|---|---|---|
| macOS | `UDCode.app/Contents/Frameworks` | Homebrew's libpq, libmariadb and its authentication plug-ins (`mariadb/plugin`), OpenSSL, and Kerberos' GSSAPI, which Homebrew's libpq links (arm64: Homebrew has no Intel builds; an Intel Mac uses a libpq and libmariadb of its own, below) |
| Linux (AppImage) | `usr/lib` in the image | Ubuntu 22.04's libpq5 and libmariadb3 (and its plug-ins), with the libraries they link (OpenSSL, GSSAPI, LDAP and theirs) |
| Windows | beside `UDCode.exe` | MSYS2's libpq and libmariadb, with the DLLs they link (OpenSSL and theirs) |

UDCode loads them when a connection first needs them, looking in its own
copies first and then for the system's. Each is a shared library of its own,
unmodified (on macOS but for the names they find each other by), and can be
replaced by another build of it. Their licences are in the app's
`Resources/Licenses` (`Contents/Resources/Licenses` on macOS), with a README
naming each library's version and where its source is: libpq is under the
PostgreSQL Licence, libmariadb under the LGPL 2.1, OpenSSL under the Apache
Licence 2.0, MIT Kerberos under its own BSD-style licence. MySQL's own
libmysqlclient (GPL) is not carried; a system's is still used when no
libmariadb is found.

A build of your own (Xcode, `make` on GNUstep) carries none of them: it
uses the system's, so install the ones for the databases you reach (a
connection without one says how). `make -f Makefile.apple install` copies
Homebrew's into the app it installs (`scripts/sql-clients.sh`), as the
release does.

| | PostgreSQL | MySQL and MariaDB |
|---|---|---|
| macOS | `brew install libpq` | `brew install mariadb-connector-c` |
| Debian, Ubuntu | `sudo apt install libpq5` | `sudo apt install libmariadb3` |
| Fedora | `sudo dnf install libpq` | `sudo dnf install mariadb-connector-c` |
| Windows | MSYS2's `mingw-w64-clang-x86_64-postgresql`, or PostgreSQL's installer (its `bin` on the PATH) | MSYS2's `mingw-w64-clang-x86_64-libmariadbclient`, or MariaDB Connector/C's installer |

## Core Data stores

A Core Data store opens as the entities it holds, not only as tables:

- **Entities**: each under its superentity, with its table and how many of
  its rows there are (its own: its subentities' are theirs). Double-click
  one (or Browse Rows) to browse its rows — its own and its subentities':
  a subentity's rows are in its root entity's table, told apart by `Z_ENT`.
- **Tables**: each `Z` table named by the entities whose rows it holds
  (`ZPERSON`: Person, Employee); a many-to-many join table (`Z_1TEAMS`) by
  the relationship it holds (`Person.teams`).
- **Store Metadata**: its type, UUID and model version.

In results, Core Data's dates (seconds since 2001) show as dates, and
`Z_ENT` names its entity: `2 · Employee`. `Z_PK` is the row's key, `Z_OPT`
its version.

## Browsing a table's rows

Double-click a table (or an entity) in the navigator, or choose **Browse
Rows** in its menu or the ER diagram's, and its rows open in a tab of their
own, a page of 100 at a time, with how many there are. Nothing is changed:
browsing only reads.

Over the rows, under each column's name, type what its rows are to be —
query by example. What is typed is a value, never SQL: each becomes a
parameter.

| Typed | Rows whose value is |
|---|---|
| `Ann`, `5` | that (a number where the column holds numbers) |
| `> 5`, `<= 3`, `<> x` | compared (`>=`, `<`, `=` and `!=` too) |
| `NULL`, `NOT NULL` | NULL, or not |
| `Ann*`, `%ann%` | like it: `*` and `%` stand for any text, case aside |
| `1..10` | between the two, both included |
| `a, b, c` | one of them |
| `!x`, `not x` | not so (any of the above) |
| `'x'`, `"5, 6"` | the text in quotes, as it is |

An empty condition shows an example of what its column takes (`e.g. > 5`,
`e.g. Ann*`), and its tooltip all of the above. The ▾ at a condition's
right (or a right-click) offers them as a menu — Equal To, Greater Than,
Like, Between, One Of, Is NULL, Not… — made of what is typed: `5` and
Greater Than make `> 5`, and what still wants a value (Between, One Of) is
left to type.

The conditions in a row all hold; **Or** adds a row of them, and rows
meeting any row are shown (− takes one away, **Clear** all). A condition
that can't be read says why and turns red. In a Core Data store, dates are
typed as dates (`2024-05-01`, `> 2024-05-01 14:30`: a day alone is the
whole day) and `Z_ENT` by entity name (`Employee`).

Click a column's name to sort by it, again for the other way (▲ ▼); the
column clicked before sorts within it. ◀ and ▶ turn the pages. **Show
SQL** opens the query as a document of its own, its values written in, to
change and run; the rows selected copy as tab-separated text (Copy with
Column Names, their names first).

## Queries by example, across tables

**New Query by Example**, in a database's menu in the navigator (or a
table's: the query begun with it), opens a query by example of tables,
joined, as Zloof's QBE and Paradox made them, untitled; Save asks where
it is kept, as a file of its own (`.qbe`: JSON, as git diffs it), its
database remembered with it. Opening a `.qbe` file brings up its
editor — the file's text is its model, as VS Code's custom text editors
are of theirs: Save, Undo and its tab's dot are the document's, and
**Show as Text** shows the file as it is (the Query by Example language
mode: JSON).

- **Skeletons.** Each table asked of has a skeleton, one under another:
  its columns, and rows under them. **Add Table** adds one, joined to those
  there along their foreign keys. Each row is a row of its table (a tuple
  variable); **Add Row** adds another.
- **What is typed** under a column:

  | Typed | Means |
  |---|---|
  | `P.` | printed: a column of the answer (before anything else too: `P.> 6`) |
  | `_c` | an example element: the same one in two rows' columns joins them |
  | `> _c` | compared with what `_c` is (`=`, `<`, `<=`, `>=`, `<>` too) |
  | `Ann`, `> 5`, `Ann*`, `1..10`, `a, b`, `NULL`, `!x` | a condition, as in the browser |

  The ▾ (or a right-click) offers them: Print, an example element (new, or
  one in the query), the comparisons, Remove This Row.
- **A row's ¬ or !**: `¬` is a row that is not there (customers no order
  refers to); `!` keeps the rows it is linked to where it has no match (a
  left join: its columns NULL; its own conditions don't drop them).
- **Alternatives.** Rows linked by their example elements are one
  alternative, holding a row of the first table; the answer is any of them
  (alternatives that print the same columns). Printed is what `P.` marks;
  with none, the first table's columns.

The query isn't tied to a connection: the database it is asked of is
chosen at its top (and remembered for the file, as a SQL document's), so
the same file is asked of staging and production; its tables are found by
name there (one missing is said). **Run** shows its answer (a column's
name sorts by it); **Show SQL** opens its SQL as a document, **Copy SQL**
puts it on the clipboard — plain SQL, the chosen database's dialect, its
values written in — for an app to run.

## Running a query

A `.sql` document is run against a database: the one chosen at the top of
its results (the window's only one, if there is just one).

| | |
|---|---|
| **Run Statement** (⌘↩) | the statement at the caret, or the selection's statements |
| **Run All** (⇧⌘↩) | every statement, in turn, stopping at the first that fails |
| **Stop** | the statement running, stopped (libpq's cancel, MySQL's `KILL QUERY`, SQLite's interrupt) |

Statements are split at their semicolons, not inside strings, quoted names,
comments or PostgreSQL's `$$…$$`.

**Parameters** — `?`, `$1`, `:name`, `@name` (not in MySQL, whose `@x` is a
variable) — are asked for in a sheet before the statement runs, the last
values offered again. A value that reads as a number is a number; write
`'0042'` for text that looks like one; NULL is a checkbox. Each database gets
them its own way: `$1, $2…` for PostgreSQL, `?` for SQLite and MySQL.

**Results** are under the query: each statement's — its first thousand rows
in a grid, or the rows it changed — and **Messages**, what ran, how long it
took and what failed (with the server's SQLSTATE). NULL is set apart from
text, a blob shows its size. Copy (or Copy with Column Names) copies the rows
selected as tab-separated text. A statement that creates, alters or drops
something reads the schema again.

## ER diagrams

**Show ER Diagram**, in a database's menu in the navigator, opens its
diagram in an editor tab: each table a box of its columns (the primary and
foreign keys marked, each column's type at the right), each foreign key a
line in crow's-foot notation — many at the table that refers, one at the
table referred to (zero or one when the key may be NULL) — routed at right
angles around the other boxes. A table that refers to itself loops back
into its own box.

A Core Data store declares no foreign keys, so its lines are inferred and
drawn dashed: a join table (`Z_1TEAMS`) to its entities' tables, and a
to-one column named as a table (`ZTEAM`) to that table. Core Data's own
tables (`Z_PRIMARYKEY`, `Z_METADATA`) are left out; a box names the entities
whose rows its table holds.

The tables are laid out in layers, the ones referred to first, until they
are moved. Drag one (or a selection) and its lines follow, their bends kept
where they can be; moves are undone with ⌘Z, and where the tables were left
is kept for the next time. **Arrange** lays them out again. Zoom with the
buttons or ⌘ and the scroll wheel. **Export** saves the diagram as PDF, PNG
or SVG; **Print…** prints it.

A table (its header), a column (its row) or a line is selected with a
click; the one selected is described under the toolbar
(`orders.customer INTEGER NOT NULL · refers to customers`). A selected
line is drawn over the rest, the columns at both its ends marked; a
selected column drags its table. Each has a menu, and a double-click runs
its first item:

| | | |
|---|---|---|
| **A table** | Browse Rows | New Query, Copy Name |
| **A column** | Select Values: each value and how many rows have it, the commonest first | New Query (`WHERE column = `), Copy Name |
| **A line** | Select Joined Rows: the two tables joined on the key | New Query (the join written out), Copy (`orders.customer → customers.id`) |

The drawing, layout, routing and canvas are
[DiagramKit](https://github.com/ashalkhakov/DiagramKit)'s.

## How it is built

The SQL extension (`Plugins/SQL`, SQL.bundle) brings all of it; UDCodeKit
only offers what any extension may use: a navigator of its own, items in the
Editor menu, an area under an editor and a tab of its own (`UDWorkbench`). The SQL mode itself
— highlighting, the jump bar's outline — is the `tree-sitter-sql` bundle's.

| | |
|---|---|
| `UDSQLConnection` | a connection: SQLite's (linked), PostgreSQL's (libpq) and MySQL's (libmariadb), loaded when first needed (`UDSQLLibrary`: UDCode's own copies first, then the system's) |
| `UDSQLText` | SQL read as far as running it needs: statements, the one at the caret, parameters in each driver's style |
| `UDSQLSchema` | tables, views, columns, keys and indexes from each catalogue; a Core Data store read as one |
| `UDSQLRunner` | a connection's work off the main thread, one operation at a time |
| `UDSQLDatabases` | a window's connections, which database each document uses, running |
| `UDSQLQbE` | query by example: what is typed under each column as a WHERE of parameters, an order, pages, a count |
| `UDSQLBrowserViewController` | a table's rows browsed: the conditions over them, sorting, paging, Show SQL |
| `UDSQLAlgebra` | relational algebra (tables as tuple variables, joins, σ, π, ∪, order, page, count; predicates; expressions) and the SQL written from it |
| `UDSQLExampleQuery` | query by example as Zloof made it: skeletons, P., example elements, ¬ and ! rows, alternatives; as algebra |
| `UDSQLExampleFile` | a `.qbe` file: its skeletons by table name, its rows, its order; asked of a database |
| `UDSQLExampleViewController` | the `.qbe` editor (VS Code's custom text editor's way): its skeletons (`UDSQLSkeletonViewController`), its connection, its answer |
| `UDSQLDiagram` | a schema's ER diagram: its boxes, links (declared or inferred), layout, routes and drawing, on DiagramKit |
| `UDSQLDiagramViewController` | the diagram's tab: DiagramKit's canvas, Arrange, zoom, export, a table's menu |

Its tests run SQLite everywhere, and PostgreSQL, MySQL and MariaDB when a
server is named (`UD_TEST_POSTGRES_URL`, `UD_TEST_MYSQL_URL`,
`UD_TEST_MARIADB_URL`; CI's Linux job starts all three).
