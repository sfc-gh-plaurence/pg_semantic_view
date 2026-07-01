# pg_semantic_view

## SQL-first prototype architecture

This repository explores a PostgreSQL extension that provides a semantic layer similar in spirit to Snowflake Semantic Views, but implemented in a PostgreSQL-friendly way.

## Current prototype implementation

The repository now includes a SQL-first prototype extension:

- `pg_semantic_view.control`
  - extension metadata
- `Makefile`
  - PGXS build/install entry point
- `sql/pg_semantic_view--0.1.0.sql`
  - schema, catalog tables, metadata views, and PL/pgSQL APIs
- `examples/demo.sql`
  - end-to-end example that creates a semantic model and compiles a query
- `scripts/validate_extension_layout.py`
  - lightweight static validation for the repository layout

The implementation currently supports:

- extension-owned catalog tables under the `semantic` schema
- `semantic.create_view(...)` for loading a normalized JSONB model
- helper APIs such as `add_logical_table`, `add_relationship`, `add_dimension`, `add_fact`, and `add_metric`
- `semantic.compile_sql(...)` for generating executable PostgreSQL SQL
- `semantic.query(...)` for executing compiled semantic queries
- `semantic.import_osi(...)`, `semantic.import_snowflake_view(...)`, and `semantic.export_osi(...)` as interchange and reuse helpers
- `semantic.meta_*` views for tool and AI inspection
- qualified semantic names for dimensions, facts, and metrics, in addition to local object names
- structured relationship metadata, including join columns and relationship expression language
- canonical expression storage for dimensions and facts, not just metrics
- explicit storage for SQL-generation guidance, question-categorization guidance, and verified-query metadata
- direct compilation of derived metrics through registered metric dependencies

### Installation guides

- Standard PostgreSQL installation: use `CREATE EXTENSION pg_semantic_view;` after the extension is installed into your PostgreSQL environment.
- Snowflake Postgres installation: see [`docs/installing-on-snowflake-postgres.md`](docs/installing-on-snowflake-postgres.md) for the managed-service-specific install flow. The short version is that Snowflake Postgres should currently use the SQL file directly instead of `CREATE EXTENSION pg_semantic_view;`.
- Snowflake-shaped JSON import guide: see [`docs/importing-snowflake-semantic-json.md`](docs/importing-snowflake-semantic-json.md) for stronger examples of `semantic.import_snowflake_view(...)`.

### Sample data guide

- TPC-DS-style sample-data walkthrough for PostgreSQL and Snowflake Postgres: see [`docs/using-sample-data-in-postgres.md`](docs/using-sample-data-in-postgres.md).

### Quick start

After installing the extension in a PostgreSQL environment:

```sql
CREATE EXTENSION pg_semantic_view;
```

Then run the example in `examples/demo.sql` to:

1. create sample physical tables,
2. register a semantic model,
3. inspect the generated SQL,
4. execute a semantic query through `semantic.query(...)`.

The recommended prototype is:

1. a function-based DDL API,
2. extension-owned catalog tables and metadata views,
3. a SQL compiler and execution API built in PL/pgSQL.

The prototype should avoid PostgreSQL parser or planner hooks at first. The goal is to prove the semantic model, validation rules, and query compilation flow before considering a future C-based integration layer.

## Prototype goals

The minimum prototype should support:

- registering a semantic view definition in PostgreSQL
- modeling logical tables, relationships, dimensions, facts, and metrics
- exposing semantic metadata for BI tools and AI agents
- compiling semantic requests into ordinary SQL
- optionally executing compiled SQL through a wrapper function

The prototype does not need to:

- add new SQL grammar such as `CREATE SEMANTIC VIEW`
- behave like a new native PostgreSQL relation type
- intercept arbitrary `SELECT ... FROM semantic_name` queries
- depend on `planner_hook` or `post_parse_analyze_hook`

## Design principles

- Use standard PostgreSQL extension objects first: schemas, tables, views, SQL functions, and PL/pgSQL functions.
- Store semantic definitions as normalized catalog rows, not only as raw JSON blobs.
- Accept JSONB in the public API because it is native to PostgreSQL and easy to validate.
- Treat SQL generation as the main execution mechanism.
- Keep the runtime interface explicit so the system is easy to debug.

## Minimum extension layout

The prototype can live under a dedicated schema such as `semantic`.

### Catalog tables

These tables hold the semantic model:

- `semantic.views`
  - one row per semantic view
  - stores name, description, default base logical table, and model-level options
- `semantic.logical_tables`
  - maps logical table names to physical tables
  - stores aliases, primary keys, unique keys, and comments
- `semantic.relationships`
  - stores join edges between logical tables
  - includes source table, target table, join expression, cardinality, and relationship name
- `semantic.dimensions`
  - stores dimension name, owning logical table, SQL expression, description, and synonyms
- `semantic.facts`
  - stores fact name, owning logical table, SQL expression, visibility, and description
- `semantic.metrics`
  - stores metric name, scope, SQL expression, visibility, aggregation type, and description
- `semantic.metric_dependencies`
  - records references between derived metrics and base metrics
- `semantic.examples`
  - stores verified queries, sample prompts, or AI guidance text

### Metadata views

These views make the semantic layer discoverable:

- `semantic.meta_views`
- `semantic.meta_logical_tables`
- `semantic.meta_relationships`
- `semantic.meta_dimensions`
- `semantic.meta_facts`
- `semantic.meta_metrics`
- `semantic.meta_examples`

An AI or text-to-SQL tool should be able to inspect these views directly.

## Public API

The first version can be implemented with SQL and PL/pgSQL functions.

### DDL-style management functions

- `semantic.create_view(...)`
- `semantic.drop_view(view_name text)`
- `semantic.add_logical_table(...)`
- `semantic.add_relationship(...)`
- `semantic.add_dimension(...)`
- `semantic.add_fact(...)`
- `semantic.add_metric(...)`

The main entry point can accept JSONB payloads:

```sql
SELECT semantic.create_view(
    view_name => 'corporate_revenue',
    definition => jsonb_build_object(
        'logical_tables', jsonb_build_array(
            jsonb_build_object(
                'name', 'orders',
                'physical_table', 'public.orders',
                'primary_key', jsonb_build_array('id')
            ),
            jsonb_build_object(
                'name', 'customers',
                'physical_table', 'public.customers',
                'primary_key', jsonb_build_array('id')
            )
        ),
        'relationships', jsonb_build_array(
            jsonb_build_object(
                'name', 'orders_to_customers',
                'from', 'orders',
                'to', 'customers',
                'on', 'orders.customer_id = customers.id'
            )
        ),
        'dimensions', jsonb_build_array(
            jsonb_build_object(
                'table', 'customers',
                'name', 'region',
                'sql', 'customers.region'
            )
        ),
        'metrics', jsonb_build_array(
            jsonb_build_object(
                'table', 'orders',
                'name', 'net_revenue',
                'sql', 'SUM(orders.subtotal - orders.discount)'
            )
        )
    )
);
```

### Query functions

Two interfaces are enough for a prototype:

- `semantic.compile_sql(...) RETURNS text`
- `semantic.query(...) RETURNS SETOF record`

Example:

```sql
SELECT semantic.compile_sql(
    semantic_view => 'corporate_revenue',
    metrics => ARRAY['net_revenue'],
    dimensions => ARRAY['region'],
    filters => '{"region":{"eq":"EMEA"}}'::jsonb
);
```

`semantic.query(...)` can call `compile_sql(...)` internally and execute the resulting SQL with `RETURN QUERY EXECUTE`.

## Internal compilation flow

The compiler should do the following:

1. Load the semantic view definition from catalog tables.
2. Resolve requested metrics, dimensions, and facts.
3. Determine which logical tables are required.
4. Build the join path from the relationship graph.
5. Expand semantic expressions into physical SQL expressions.
6. Split filters into pre-aggregation conditions when needed.
7. Build the final `SELECT`, `FROM`, `JOIN`, `WHERE`, and `GROUP BY` clauses.
8. Return generated SQL as text.

This is the core of the prototype. Even if the extension later adds C code, this logical pipeline remains the same.

## Validation rules for v1

The prototype should validate:

- referenced physical tables exist
- referenced columns exist
- relationship endpoints are known logical tables
- dimension, fact, and metric names are unique within the semantic view
- derived metrics reference only known metrics
- public queries do not expose private facts or private metrics
- the requested query only uses dimensions that are reachable from the selected metrics

Most of this validation can be done in PL/pgSQL with catalog lookups and dynamic checks against `pg_catalog`.

## Recommended implementation split

### SQL

Use SQL for:

- schema creation
- catalog tables
- indexes and constraints
- metadata views
- simple wrapper functions

### PL/pgSQL

Use PL/pgSQL for:

- `create_view` orchestration
- JSONB validation
- dependency registration
- semantic query compilation
- dynamic SQL execution

### Future C layer

Only introduce C if later versions need:

- parser or planner hooks
- parse tree inspection instead of string-based SQL generation
- more advanced caching or execution integration
- lower overhead for complex compilation

The first prototype should not require C.

## Example user workflow

1. Register a semantic model with `semantic.create_view(...)`.
2. Inspect model metadata with `semantic.meta_metrics` or `semantic.meta_dimensions`.
3. Ask the compiler for the SQL behind a semantic request.
4. Execute the request through `semantic.query(...)` or in an external client.

This keeps the semantic layer transparent and easy to test.

## Suggested implementation phases

### Phase 1: catalog and metadata

- create schema, tables, and metadata views
- implement `create_view` and `drop_view`
- validate logical tables, relationships, dimensions, and metrics

### Phase 2: compiler

- implement metric and dimension resolution
- implement join graph traversal
- generate grouped aggregate SQL

### Phase 3: execution helpers

- implement `semantic.query(...)`
- add support for examples and AI-oriented metadata inspection

### Phase 4: advanced semantics

- derived metrics
- private metrics
- multiple relationship path disambiguation
- non-additive metrics
- window metrics

## OSI compatibility

This prototype should be compatible with the Open Semantic Interchange (OSI) effort, but OSI should be treated as an interchange format rather than as the exact internal storage layout.

The recommended approach is:

- use normalized PostgreSQL catalog tables as the internal model
- import OSI YAML or JSON into those tables
- compile and execute semantic queries from the normalized model
- export the model back to OSI when interoperability is needed

This keeps the extension PostgreSQL-friendly while still allowing exchange with external semantic tools, AI agents, and BI platforms that adopt OSI.

### Compatibility model

The prototype should separate:

- **canonical semantic metadata**: business entities, relationships, metrics, dimensions, context, and extensions
- **PostgreSQL compiled form**: SQL expressions, query plans, and runtime execution details specific to PostgreSQL

This means the extension should avoid storing semantics only as raw PostgreSQL SQL strings. When possible, store enough canonical structure to reconstruct or export an OSI-compatible definition later.

### Proposed prototype-to-OSI mapping

| Prototype object | OSI concept | Notes |
| --- | --- | --- |
| `semantic.views` | semantic model | Stores the top-level model identity, description, AI context, and model-level options. |
| `semantic.logical_tables` | datasets | Each logical table maps to an OSI dataset with source mapping to a physical PostgreSQL table. |
| `semantic.relationships` | relationships | Stores join edges, join keys, and cardinality metadata between datasets. |
| `semantic.dimensions` | dimensions | Maps business-facing grouping and filtering fields to dataset fields or expressions. |
| `semantic.facts` | dataset fields / measure inputs | Acts as row-level building blocks for metrics and dimensions. |
| `semantic.metrics` | metrics / measures | Stores aggregate business calculations and derived metrics. |
| `semantic.examples` | AI context / example queries / contextual metadata | Holds verified query examples, prompt hints, and tool-facing usage guidance. |
| `extensions jsonb` columns | `custom_extensions` | Preserves vendor-specific or OSI fields that the prototype does not interpret directly. |

### Recommended schema additions for OSI support

To support strong OSI import and export, the prototype should add a small amount of interchange-oriented metadata:

- `semantic.views`
  - `source_format text`
  - `source_version text`
  - `ai_context jsonb`
  - `extensions jsonb`
- `semantic.logical_tables`
  - `dataset_kind text`
  - `source_mapping jsonb`
  - `extensions jsonb`
- `semantic.dimensions`
  - `data_type text`
  - `time_granularity text`
  - `extensions jsonb`
- `semantic.facts`
  - `data_type text`
  - `extensions jsonb`
- `semantic.metrics`
  - `expression_canonical jsonb`
  - `expression_sql text`
  - `expression_language text`
  - `extensions jsonb`

These fields are intended to preserve canonical semantic meaning, not just the compiled PostgreSQL representation.

### Import and export APIs

The prototype should expose explicit interchange functions:

```sql
SELECT semantic.import_osi(
    model_name => 'corporate_revenue',
    document => $json$
      {
        "name": "corporate_revenue"
      }
    $json$::jsonb
);

SELECT semantic.export_osi(
    model_name => 'corporate_revenue'
);
```

Optional convenience wrappers can support YAML import and export, but the core storage and validation path should use JSONB inside PostgreSQL.

### Practical compatibility rules

To remain OSI-friendly, the prototype should follow these rules:

- preserve unknown OSI fields in `extensions jsonb` instead of dropping them
- allow round-tripping of supported models even when some fields are not executed natively
- keep PostgreSQL-specific execution details out of the canonical export when possible
- treat raw SQL expressions as a compiled target, not as the only representation of a metric

### Expected compatibility level

- **Structural compatibility:** high
  - the prototype already matches the core OSI concepts of models, datasets, relationships, dimensions, and metrics
- **Import/export compatibility:** moderate to high
  - this requires explicit adapter functions and extension-preserving storage
- **Full semantic round-trip fidelity:** partial at first
  - advanced expressions and vendor-specific semantics may require staged support or partial passthrough

## Why this is the right minimum architecture

This approach proves the hardest and most valuable parts of the project first:

- semantic metadata modeling
- validation
- query compilation
- discoverability for AI and BI tools

It also keeps the prototype aligned with PostgreSQL extension norms and avoids premature investment in C-based internals before the semantic model is stable.
