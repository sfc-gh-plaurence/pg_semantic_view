# Introducing `pg_semantic_view`: a SQL-first semantic layer for PostgreSQL

PostgreSQL has excellent primitives for storing and querying data, but it still leaves a recurring analytics problem unsolved at the application layer: teams define the same business logic over and over again.

What is "net revenue"?  
What exactly counts as an "order"?  
Which dimensions are valid for a metric?  
How should an AI agent discover the right business definitions before it writes SQL?

`pg_semantic_view` is a new SQL-first PostgreSQL extension prototype that addresses those questions by adding a semantic layer inside Postgres itself.

Instead of scattering business definitions across dashboards, notebooks, data apps, and prompt templates, the extension stores semantic definitions centrally and exposes them through SQL.

## Why build a semantic layer in PostgreSQL?

Modern teams increasingly want four things at once:

1. **consistent metric definitions**
2. **shared metadata for BI and analytics**
3. **discoverable business context for AI systems**
4. **interchange across tools instead of lock-in to one vendor**

Without a semantic layer, each consumer ends up rebuilding the same concepts:

- "Revenue" is defined differently across dashboards
- joins are repeated manually in every query
- analysts have to know physical schemas instead of business entities
- AI and text-to-SQL tools guess at meaning from raw tables and column names

The result is inconsistency, duplicated logic, and a much harder path to trustworthy analytics.

`pg_semantic_view` is designed to solve that by making business concepts first-class metadata inside PostgreSQL.

## What `pg_semantic_view` is

At a high level, the extension provides:

- a catalog schema (`semantic.*`) for semantic models
- logical tables mapped to physical PostgreSQL tables
- relationships between logical tables
- dimensions, facts, and metrics
- metadata views that tools and AI agents can inspect
- a SQL compiler that turns semantic requests into ordinary PostgreSQL SQL
- import/export helpers for interchange

It is intentionally **SQL-first**:

- SQL schema objects
- PL/pgSQL functions
- JSONB-based semantic model registration
- no parser hooks
- no C extension requirement for the current prototype

That makes it portable, inspectable, and easier to deploy in standard PostgreSQL and Snowflake Postgres environments.

## The problem it solves

The extension is aimed at a specific problem:

> How do we keep business meaning close to the data, reusable across applications, and inspectable by both humans and AI?

### Before

Without a semantic layer, an analyst or application usually has to know:

- which fact table to query
- which dimensions to join
- how to define metrics correctly
- which filters are valid
- whether a similarly named metric elsewhere is actually the same thing

### After

With `pg_semantic_view`, those definitions can be stored once and reused:

- metrics live in a shared catalog
- relationships are defined centrally
- dimensions and facts are queryable as semantic metadata
- semantic queries compile into ordinary SQL
- AI and text-to-SQL systems can inspect the semantic catalog before generating SQL

This is useful for:

- embedded analytics
- BI tooling
- internal data applications
- semantic model experimentation
- AI/data-agent workflows

## How it works

The prototype currently follows three core design ideas:

1. **Function-based DDL API**
2. **Extension-owned metadata tables**
3. **Compiled semantic query execution**

In practice, that means you register a semantic view through a PostgreSQL function like:

```sql
SELECT semantic.create_view(
    p_view_name => 'corporate_revenue',
    p_definition => jsonb_build_object(
        'logical_tables', jsonb_build_array(
            jsonb_build_object(
                'name', 'orders',
                'physical_table', 'public.orders'
            ),
            jsonb_build_object(
                'name', 'customers',
                'physical_table', 'public.customers'
            )
        ),
        'relationships', jsonb_build_array(
            jsonb_build_object(
                'name', 'orders_to_customers',
                'from', 'orders',
                'to', 'customers',
                'join_sql', 'orders.customer_id = customers.id'
            )
        ),
        'dimensions', jsonb_build_array(
            jsonb_build_object(
                'table', 'customers',
                'name', 'region',
                'qualified_name', 'Customer.Region',
                'sql', 'customers.region'
            )
        ),
        'metrics', jsonb_build_array(
            jsonb_build_object(
                'table', 'orders',
                'name', 'net_revenue',
                'qualified_name', 'Orders.NetRevenue',
                'sql', 'SUM(orders.subtotal - orders.discount)'
            )
        )
    )
);
```

Once registered, the model can be queried semantically:

```sql
SELECT *
FROM semantic.query(
    p_semantic_view => 'corporate_revenue',
    p_metrics => ARRAY['Orders.NetRevenue'],
    p_dimensions => ARRAY['Customer.Region'],
    p_filters => '{"Customer.Region":{"eq":"EMEA"}}'::jsonb
) AS t(region text, net_revenue numeric);
```

The extension compiles that request into ordinary PostgreSQL SQL, which means:

- the runtime stays transparent
- generated SQL can be inspected
- the semantic layer is easy to debug

## How this relates to the Open Semantic Interchange (OSI) initiative

Snowflake's Open Semantic Interchange (OSI) initiative is aimed at a vendor-neutral way to exchange semantic metadata across tools, AI systems, and platforms.

Reference:

- Snowflake, **"Open Semantic Interchange (OSI) Updates: Specification Now Live, New Working Group Members and More"**
  - https://www.snowflake.com/en/blog/open-semantic-interchanges-specs-finalized/

That initiative matters because the semantic-layer problem is bigger than any one database engine. The industry needs a way to exchange:

- datasets
- relationships
- dimensions
- facts and measures
- metrics
- AI-facing context

without redefining them separately for every system.

## How `pg_semantic_view` is compliant with the OSI initiative

For this prototype, the right claim is:

> `pg_semantic_view` is **OSI-compliant at the interchange boundary** and **OSI-aligned in its internal model**.

That means the extension does **not** literally replace the OSI specification with its own internal schema. Instead, it uses:

- a PostgreSQL-native internal catalog model
- plus explicit import/export mappings for interchange

### Concretely, the extension now supports OSI-style interchange concepts such as:

- logical datasets / logical tables
- structured relationships
- dimensions
- facts
- metrics
- canonical expressions
- qualified semantic names
- AI guidance metadata
- verified query metadata
- extension metadata passthrough

### Interchange helpers in the prototype

The extension exposes:

- `semantic.import_osi(...)`
- `semantic.export_osi(...)`

These functions make OSI a practical interchange layer instead of just a conceptual alignment target.

### Why this matters

This approach gives the extension two benefits at once:

1. **PostgreSQL-native execution and metadata storage**
2. **vendor-neutral portability at the interchange boundary**

That is the right trade-off for a SQL-first prototype.

## Reusing Snowflake semantic views in PostgreSQL

A second major goal of the project is to make Snowflake semantic-view reuse easier in PostgreSQL.

The prototype now supports:

- qualified semantic names like `Item.Brand` and `StoreSales.TotalSalesQuantity`
- structured relationship metadata
- explicit SQL generation instructions and question categorization instructions
- verified query metadata
- `semantic.import_snowflake_view(...)`

That means a Snowflake-shaped semantic definition can be converted into JSONB and imported into PostgreSQL with much less rewriting than a flat metric catalog would require.

The extension still does **not** try to emulate Snowflake's native SQL grammar exactly. You do not write:

```sql
CREATE SEMANTIC VIEW ...
```

or:

```sql
SELECT * FROM SEMANTIC_VIEW(...)
```

Instead, the extension provides PostgreSQL-style equivalents through SQL functions and metadata tables.

## Example: TPC-DS-style sample data

The repository includes a TPC-DS-style walkthrough and stronger Snowflake-shaped JSON examples for side-by-side comparison.

Relevant docs:

- [`docs/using-sample-data-in-postgres.md`](using-sample-data-in-postgres.md)
- [`docs/importing-snowflake-semantic-json.md`](importing-snowflake-semantic-json.md)

### Example semantic query

Using the TPC-DS-style sample subset, a Snowflake-style question such as:

> What are the top selling brands in Texas Books during December 2002?

can be expressed through the prototype as:

```sql
SELECT *
FROM semantic.query(
    p_semantic_view => 'tpcds_semantic_view_sm',
    p_metrics => ARRAY['StoreSales.TotalSalesQuantity'],
    p_dimensions => ARRAY[
        'Item.Brand',
        'Item.Category',
        'Date.Year',
        'Date.Month',
        'Store.State'
    ],
    p_filters => '{
      "Date.Year":{"eq":"2002"},
      "Date.Month":{"eq":"12"},
      "Store.State":{"eq":"TX"},
      "Item.Category":{"eq":"Books"}
    }'::jsonb
) AS t(
    item_brand text,
    item_category text,
    date_year integer,
    date_month integer,
    store_state text,
    total_sales_quantity numeric
)
ORDER BY total_sales_quantity DESC
LIMIT 10;
```

This does not use Snowflake's native `SEMANTIC_VIEW(...)` surface, but it is designed to produce similar analytical results from the same style of sample data.

## Why this extension is interesting

`pg_semantic_view` is interesting for two reasons.

### 1. It treats PostgreSQL as a semantic runtime, not just a storage engine

The extension shows that PostgreSQL can host:

- semantic metadata
- metric definitions
- relationship logic
- AI-facing context
- query compilation

without waiting for a new native SQL object type in PostgreSQL core.

### 2. It creates a bridge between PostgreSQL and open semantic interchange

Instead of choosing between:

- "native PostgreSQL only"
- or "interchange standard only"

the prototype uses both:

- internal PostgreSQL catalogs for execution
- interchange functions for portability

That is a practical architecture for teams that want:

- strong local control
- SQL transparency
- future portability

## Where the project can go next

There is still plenty of room to grow, including:

- richer Snowflake JSON import coverage
- stronger OSI round-trip testing
- more advanced metric semantics
- expanded regression tests in a live PostgreSQL environment
- higher-fidelity compatibility with Snowflake-style semantic query patterns

But even in its current form, the extension already demonstrates a strong thesis:

> a real semantic layer for PostgreSQL can be built using SQL, PL/pgSQL, and open interchange concepts.

## Getting started

To explore the prototype:

1. install the extension in PostgreSQL, or install the SQL bundle in Snowflake Postgres
2. load the sample schema and data
3. register a semantic model
4. inspect `semantic.meta_*`
5. run `semantic.compile_sql(...)`
6. execute `semantic.query(...)`

If you want the fastest path into the examples, start with:

- [`docs/using-sample-data-in-postgres.md`](using-sample-data-in-postgres.md)
- [`docs/importing-snowflake-semantic-json.md`](importing-snowflake-semantic-json.md)
