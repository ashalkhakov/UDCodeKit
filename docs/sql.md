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
**Passwords are never written**: asked for when the server wants one, kept
until UDCode quits.

Open a connection and its tables and views are listed, each with its
columns (type, primary and foreign keys, NOT NULL), indexes and foreign
keys. Double-click a table for its first rows.

SQLite is built in. PostgreSQL's and MySQL's client libraries are not: UDCode
uses yours, so install the ones for the databases you reach (a connection
without one says how):

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
  one (or Select Rows) for its rows — its own and its subentities': a
  subentity's rows are in its root entity's table, told apart by `Z_ENT`.
- **Tables**: each `Z` table named by the entities whose rows it holds
  (`ZPERSON`: Person, Employee); a many-to-many join table (`Z_1TEAMS`) by
  the relationship it holds (`Person.teams`).
- **Store Metadata**: its type, UUID and model version.

In results, Core Data's dates (seconds since 2001) show as dates, and
`Z_ENT` names its entity: `2 · Employee`. `Z_PK` is the row's key, `Z_OPT`
its version.

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
| **A table** | Select Rows | New Query, Copy Name |
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
| `UDSQLConnection` | a connection: SQLite's (linked), PostgreSQL's (libpq) and MySQL's (libmariadb), loaded when first needed |
| `UDSQLText` | SQL read as far as running it needs: statements, the one at the caret, parameters in each driver's style |
| `UDSQLSchema` | tables, views, columns, keys and indexes from each catalogue; a Core Data store read as one |
| `UDSQLRunner` | a connection's work off the main thread, one operation at a time |
| `UDSQLDatabases` | a window's connections, which database each document uses, running |
| `UDSQLDiagram` | a schema's ER diagram: its boxes, links (declared or inferred), layout, routes and drawing, on DiagramKit |
| `UDSQLDiagramViewController` | the diagram's tab: DiagramKit's canvas, Arrange, zoom, export, a table's menu |

Its tests run SQLite everywhere, and PostgreSQL, MySQL and MariaDB when a
server is named (`UD_TEST_POSTGRES_URL`, `UD_TEST_MYSQL_URL`,
`UD_TEST_MARIADB_URL`; CI's Linux job starts all three).
