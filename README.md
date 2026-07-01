# pg_semantic_view

## SQL-first prototype architecture

This repository explores a PostgreSQL extension that provides a semantic layer similar in spirit to Snowflake Semantic Views, but implemented in a PostgreSQL-friendly way.

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

## Why this is the right minimum architecture

This approach proves the hardest and most valuable parts of the project first:

- semantic metadata modeling
- validation
- query compilation
- discoverability for AI and BI tools

It also keeps the prototype aligned with PostgreSQL extension norms and avoids premature investment in C-based internals before the semantic model is stable.
