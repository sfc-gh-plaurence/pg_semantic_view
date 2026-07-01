# Using sample data in Postgres / Snowflake Postgres with the prototype

This guide shows how to use a small TPC-DS-style sample dataset with the current `pg_semantic_view` prototype in either:

- standard PostgreSQL, or
- Snowflake Postgres

The goal is not to reproduce Snowflake Semantic Views syntax exactly. The goal is to use the same **basic sample-data approach** and produce **similar analytical results** with the prototype.

## Original reference example

This walkthrough is intentionally modeled after Snowflake's semantic-view getting-started example so that you can compare the two approaches side by side:

- Chanin Nantasenamat, **"Getting Started with Snowflake Semantic View"**
  - https://medium.com/snowflake/getting-started-with-snowflake-semantic-view-7eced29abe6f

For comparison purposes:

- this guide keeps the same general star-schema pattern
- it uses a similar TPC-DS-style subset built around `store_sales`, `item`, `date_dim`, and `store`
- it targets similar business questions, such as top-selling brands by filtered sales quantity
- it translates Snowflake-native semantic-view syntax into the prototype's `semantic.create_view(...)`, `semantic.compile_sql(...)`, and `semantic.query(...)` APIs

## What this guide covers

This walkthrough shows how to:

1. create a small TPC-DS-style schema in PostgreSQL
2. load or synthesize a small subset of sample data
3. register a semantic model with `semantic.create_view(...)`
4. run metric-and-dimension queries through `semantic.query(...)`
5. produce results similar to the common Snowflake example pattern, such as:
   - total sales quantity by brand
   - filtered by year, month, state, and category
   - sorted to find the top results

## Scope and assumptions

This guide uses a reduced subset of TPC-DS-style entities:

- `store_sales`
- `item`
- `date_dim`
- `store`

This is enough to reproduce the most important semantic pattern in the Snowflake example:

- a fact table
- several dimension tables
- business dimensions for slicing/filtering
- at least one aggregate metric

## Choose a data-loading strategy

You have two practical options.

### Option A: load a real subset of Snowflake sample data

If you already have access to Snowflake sample data, export a subset of the rows you need and import them into PostgreSQL or Snowflake Postgres.

Recommended flow:

1. select a manageable row subset from the source tables
2. export it as CSV, Parquet, or another convenient interchange format
3. create the target PostgreSQL tables shown below
4. import the data with `COPY`, `\copy`, or your preferred ETL tool

This gives you the closest match to the original Snowflake demo.

### Option B: create a tiny local demo dataset

If your main goal is to verify semantic modeling behavior rather than benchmark-scale results, insert a small hand-crafted dataset directly into PostgreSQL.

This is the fastest way to validate:

- relationships
- dimension definitions
- metric definitions
- compiled SQL output
- filtered aggregate results

## Step 1: install the prototype

### Standard PostgreSQL

If the extension is installed in your PostgreSQL environment:

```sql
CREATE EXTENSION pg_semantic_view;
```

### Snowflake Postgres

Use the SQL bundle installation path described in:

- [`docs/installing-on-snowflake-postgres.md`](installing-on-snowflake-postgres.md)

In short:

```bash
psql "host=<host> port=<port> dbname=<database> user=<user> sslmode=require" \
  -v ON_ERROR_STOP=1 \
  -f sql/pg_semantic_view--0.1.0.sql
```

## Step 2: create a TPC-DS-style subset schema

The following schema keeps the familiar table names and column names from the TPC-DS pattern, but only includes the fields needed for a basic semantic demo.

```sql
CREATE TABLE public.item (
    i_item_sk bigint PRIMARY KEY,
    i_brand text NOT NULL,
    i_category text NOT NULL
);

CREATE TABLE public.date_dim (
    d_date_sk bigint PRIMARY KEY,
    d_year integer NOT NULL,
    d_moy integer NOT NULL
);

CREATE TABLE public.store (
    s_store_sk bigint PRIMARY KEY,
    s_state text NOT NULL
);

CREATE TABLE public.store_sales (
    ss_sold_date_sk bigint NOT NULL REFERENCES public.date_dim(d_date_sk),
    ss_item_sk bigint NOT NULL REFERENCES public.item(i_item_sk),
    ss_store_sk bigint NOT NULL REFERENCES public.store(s_store_sk),
    ss_quantity numeric(18, 2) NOT NULL
);
```

## Step 3: load a small dataset

### Minimal inline demo dataset

Use this if you want a quick smoke test:

```sql
INSERT INTO public.item (i_item_sk, i_brand, i_category) VALUES
  (1, 'Brand A', 'Books'),
  (2, 'Brand B', 'Books'),
  (3, 'Brand C', 'Electronics');

INSERT INTO public.date_dim (d_date_sk, d_year, d_moy) VALUES
  (101, 2002, 12),
  (102, 2003, 1);

INSERT INTO public.store (s_store_sk, s_state) VALUES
  (201, 'TX'),
  (202, 'CA');

INSERT INTO public.store_sales (ss_sold_date_sk, ss_item_sk, ss_store_sk, ss_quantity) VALUES
  (101, 1, 201, 15),
  (101, 1, 201, 10),
  (101, 2, 201, 25),
  (101, 2, 202, 8),
  (101, 3, 201, 4),
  (102, 1, 201, 12);
```

### CSV import pattern

If you exported data externally, you can load it with `\copy` from a local machine:

```bash
\copy public.item FROM 'item.csv' WITH (FORMAT csv, HEADER true)
\copy public.date_dim FROM 'date_dim.csv' WITH (FORMAT csv, HEADER true)
\copy public.store FROM 'store.csv' WITH (FORMAT csv, HEADER true)
\copy public.store_sales FROM 'store_sales.csv' WITH (FORMAT csv, HEADER true)
```

## Step 4: register the semantic model

The current prototype uses flattened semantic names inside a view. Instead of identifiers like `Item.Brand` and `Date.Year`, define unique names such as:

- `item_brand`
- `item_category`
- `date_year`
- `date_month`
- `store_state`
- `total_sales_quantity`

Register the semantic model like this:

```sql
SELECT semantic.create_view(
    p_view_name => 'tpcds_semantic_view_sm',
    p_definition => jsonb_build_object(
        'description', 'TPC-DS-style sample semantic model for Postgres',
        'default_base_logical_table', 'store_sales',
        'logical_tables', jsonb_build_array(
            jsonb_build_object(
                'name', 'store_sales',
                'physical_table', 'public.store_sales',
                'dataset_kind', 'fact'
            ),
            jsonb_build_object(
                'name', 'item',
                'physical_table', 'public.item',
                'primary_key', jsonb_build_array('i_item_sk'),
                'dataset_kind', 'dimension'
            ),
            jsonb_build_object(
                'name', 'date_dim',
                'physical_table', 'public.date_dim',
                'primary_key', jsonb_build_array('d_date_sk'),
                'dataset_kind', 'dimension'
            ),
            jsonb_build_object(
                'name', 'store',
                'physical_table', 'public.store',
                'primary_key', jsonb_build_array('s_store_sk'),
                'dataset_kind', 'dimension'
            )
        ),
        'relationships', jsonb_build_array(
            jsonb_build_object(
                'name', 'store_sales_to_item',
                'from', 'store_sales',
                'to', 'item',
                'join_sql', 'store_sales.ss_item_sk = item.i_item_sk',
                'cardinality', 'many_to_one'
            ),
            jsonb_build_object(
                'name', 'store_sales_to_date_dim',
                'from', 'store_sales',
                'to', 'date_dim',
                'join_sql', 'store_sales.ss_sold_date_sk = date_dim.d_date_sk',
                'cardinality', 'many_to_one'
            ),
            jsonb_build_object(
                'name', 'store_sales_to_store',
                'from', 'store_sales',
                'to', 'store',
                'join_sql', 'store_sales.ss_store_sk = store.s_store_sk',
                'cardinality', 'many_to_one'
            )
        ),
        'dimensions', jsonb_build_array(
            jsonb_build_object(
                'table', 'item',
                'name', 'item_brand',
                'sql', 'item.i_brand'
            ),
            jsonb_build_object(
                'table', 'item',
                'name', 'item_category',
                'sql', 'item.i_category'
            ),
            jsonb_build_object(
                'table', 'date_dim',
                'name', 'date_year',
                'sql', 'date_dim.d_year',
                'data_type', 'integer'
            ),
            jsonb_build_object(
                'table', 'date_dim',
                'name', 'date_month',
                'sql', 'date_dim.d_moy',
                'data_type', 'integer'
            ),
            jsonb_build_object(
                'table', 'store',
                'name', 'store_state',
                'sql', 'store.s_state'
            )
        ),
        'metrics', jsonb_build_array(
            jsonb_build_object(
                'table', 'store_sales',
                'name', 'total_sales_quantity',
                'sql', 'SUM(store_sales.ss_quantity)',
                'aggregation_kind', 'sum'
            )
        )
    )
);
```

## Step 5: inspect the semantic metadata

Check that the semantic objects are registered:

```sql
SELECT * FROM semantic.meta_views;
SELECT * FROM semantic.meta_logical_tables WHERE view_name = 'tpcds_semantic_view_sm';
SELECT * FROM semantic.meta_relationships WHERE view_name = 'tpcds_semantic_view_sm';
SELECT * FROM semantic.meta_dimensions WHERE view_name = 'tpcds_semantic_view_sm';
SELECT * FROM semantic.meta_metrics WHERE view_name = 'tpcds_semantic_view_sm';
```

## Step 6: compile a semantic query

This query follows the same business intent as the common Snowflake example:

- group by brand, category, year, month, and state
- return total sales quantity
- filter to year 2002, month 12, state TX, category Books

```sql
SELECT semantic.compile_sql(
    p_semantic_view => 'tpcds_semantic_view_sm',
    p_metrics => ARRAY['total_sales_quantity'],
    p_dimensions => ARRAY[
        'item_brand',
        'item_category',
        'date_year',
        'date_month',
        'store_state'
    ],
    p_filters => '{
      "date_year":{"eq":"2002"},
      "date_month":{"eq":"12"},
      "store_state":{"eq":"TX"},
      "item_category":{"eq":"Books"}
    }'::jsonb
);
```

This returns ordinary PostgreSQL SQL text, which is useful for debugging and comparison.

## Step 7: execute the semantic query

```sql
SELECT *
FROM semantic.query(
    p_semantic_view => 'tpcds_semantic_view_sm',
    p_metrics => ARRAY['total_sales_quantity'],
    p_dimensions => ARRAY[
        'item_brand',
        'item_category',
        'date_year',
        'date_month',
        'store_state'
    ],
    p_filters => '{
      "date_year":{"eq":"2002"},
      "date_month":{"eq":"12"},
      "store_state":{"eq":"TX"},
      "item_category":{"eq":"Books"}
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

## Step 8: compare to the Snowflake-style workflow

The business outcome is similar, even though the interface is different.

### Snowflake-style concept

```sql
SELECT * FROM SEMANTIC_VIEW(...)
```

### Prototype-style concept

```sql
SELECT *
FROM semantic.query(...)
```

The prototype currently gives you:

- semantic modeling
- metadata introspection
- compiled SQL generation
- semantic query execution

It does not currently give you:

- native `CREATE SEMANTIC VIEW` syntax
- the `SEMANTIC_VIEW(...)` query surface
- Cortex Analyst integration
- natural language querying

## Notes for Snowflake Postgres

If you are using Snowflake Postgres:

- install the prototype with the SQL bundle, not `CREATE EXTENSION pg_semantic_view`
- use the same schema and model definition shown above
- load data with ordinary PostgreSQL tools such as `psql` and `\copy`

Snowflake Postgres is a good fit for this prototype because the implementation is SQL and PL/pgSQL only.

## Recommended first milestone

If you want to validate “similar results” quickly, use this checklist:

1. load the four-table subset
2. register the semantic view
3. run `semantic.compile_sql(...)`
4. run `semantic.query(...)`
5. compare the result to a hand-written SQL aggregate over the same tables

If those results match, then the prototype is successfully reproducing the core semantic-layer behavior for the sample data approach.
