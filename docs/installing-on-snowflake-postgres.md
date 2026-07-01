# Installing the prototype on Snowflake Postgres

This document describes how to install the current `pg_semantic_view` prototype on Snowflake Postgres.

## Important limitation

Snowflake Postgres supports PostgreSQL and PL/pgSQL, but extension installation is managed by Snowflake. In practice, that means:

- you **can** enable extensions that appear in `pg_available_extensions`
- you **cannot assume** that a custom PGXS-built extension such as `pg_semantic_view` can be installed with:

```sql
CREATE EXTENSION pg_semantic_view;
```

At the time this guide was written, the correct approach for this repository is to install the prototype as a **SQL bundle**, not as a Snowflake-managed extension package.

## What this means for this repository

Use these files differently on Snowflake Postgres:

- `pg_semantic_view.control`
  - not used directly
- `Makefile`
  - not used directly
- `sql/pg_semantic_view--0.1.0.sql`
  - this is the main install artifact for Snowflake Postgres
- `examples/demo.sql`
  - useful as a reference for standard PostgreSQL installs
- `examples/demo_snowflake_postgres.sql`
  - ready-to-run example for Snowflake Postgres after the SQL bundle is installed

## Prerequisites

Before installing the prototype, make sure:

1. you have a running Snowflake Postgres instance
2. you can connect to it with a standard PostgreSQL client such as `psql`
3. you are connected with a role that can create schemas, tables, views, and functions in the target database
4. PL/pgSQL is available, which Snowflake Postgres documents as supported

## Recommended installation model

Install the prototype into a dedicated database or into a clean test environment first.

Because the installer creates the `semantic` schema and a large set of tables, functions, and views, the safest first deployment is:

- a fresh database for evaluation, or
- a non-production schema-isolated test environment

## Step 1: Connect to the Snowflake Postgres instance

Use the connection string provided by Snowflake Postgres and connect with `psql` or another PostgreSQL client.

Example:

```bash
psql "host=<host> port=<port> dbname=<database> user=<user> sslmode=require"
```

## Step 2: Inspect the managed extension catalog

This step is mainly to confirm that `pg_semantic_view` is not expected to exist as a Snowflake-managed extension.

```sql
SELECT name, default_version, installed_version
FROM pg_available_extensions
ORDER BY name;
```

If `pg_semantic_view` is not listed, that is expected for this prototype.

You can also confirm currently enabled extensions:

```sql
SELECT extname
FROM pg_extension
ORDER BY extname;
```

## Step 3: Create or select the target database

If you want a clean evaluation database:

```sql
CREATE DATABASE semantic_lab;
```

Reconnect to it:

```bash
psql "host=<host> port=<port> dbname=semantic_lab user=<user> sslmode=require"
```

## Step 4: Install the prototype by running the SQL file directly

From the repository root, execute:

```bash
psql "host=<host> port=<port> dbname=<database> user=<user> sslmode=require" \
  -v ON_ERROR_STOP=1 \
  -f sql/pg_semantic_view--0.1.0.sql
```

This creates:

- the `semantic` schema
- catalog tables such as `semantic.views`, `semantic.logical_tables`, and `semantic.metrics`
- PL/pgSQL APIs such as `semantic.create_view(...)`, `semantic.compile_sql(...)`, and `semantic.query(...)`
- metadata views such as `semantic.meta_metrics`

## Step 5: Verify the installation

After the SQL file finishes, verify that the schema and key functions exist.

### Check the schema

```sql
SELECT schema_name
FROM information_schema.schemata
WHERE schema_name = 'semantic';
```

### Check the catalog tables

```sql
SELECT table_name
FROM information_schema.tables
WHERE table_schema = 'semantic'
ORDER BY table_name;
```

### Check the functions

```sql
SELECT routine_name
FROM information_schema.routines
WHERE routine_schema = 'semantic'
ORDER BY routine_name;
```

## Step 6: Load a sample semantic model

After the SQL bundle is installed, run:

```bash
psql "host=<host> port=<port> dbname=<database> user=<user> sslmode=require" \
  -v ON_ERROR_STOP=1 \
  -f examples/demo_snowflake_postgres.sql
```

If you prefer to inspect the calls inline, the key entry point is:

```sql
SELECT semantic.create_view(
    p_view_name => 'corporate_revenue',
    p_definition => jsonb_build_object(
        'description', 'Revenue model used in demo.sql',
        'default_base_logical_table', 'orders',
        'logical_tables', jsonb_build_array(
            jsonb_build_object(
                'name', 'orders',
                'physical_table', 'public.orders',
                'primary_key', jsonb_build_array('id'),
                'dataset_kind', 'fact'
            ),
            jsonb_build_object(
                'name', 'customers',
                'physical_table', 'public.customers',
                'primary_key', jsonb_build_array('id'),
                'dataset_kind', 'dimension'
            )
        ),
        'relationships', jsonb_build_array(
            jsonb_build_object(
                'name', 'orders_to_customers',
                'from', 'orders',
                'to', 'customers',
                'join_sql', 'orders.customer_id = customers.id',
                'cardinality', 'many_to_one'
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

## Step 7: Compile and inspect generated SQL

Once a semantic model is loaded, verify compilation:

```sql
SELECT semantic.compile_sql(
    p_semantic_view => 'corporate_revenue',
    p_metrics => ARRAY['net_revenue'],
    p_dimensions => ARRAY['region'],
    p_filters => '{"region":{"eq":"EMEA"}}'::jsonb
);
```

This should return ordinary PostgreSQL SQL text.

## Step 8: Query through the semantic wrapper

Example:

```sql
SELECT *
FROM semantic.query(
    p_semantic_view => 'corporate_revenue',
    p_metrics => ARRAY['net_revenue'],
    p_dimensions => ARRAY['region'],
    p_filters => '{"region":{"eq":"EMEA"}}'::jsonb
) AS t(region text, net_revenue numeric);
```

## Operational notes

### This is not a native Snowflake-managed extension

This prototype is currently installed by executing SQL directly. That means:

- `CREATE EXTENSION pg_semantic_view;` is not the expected installation path on Snowflake Postgres today
- version upgrades should currently be treated like SQL migrations
- uninstall should be done by dropping the `semantic` schema if the environment is dedicated to testing

Example cleanup:

```sql
DROP SCHEMA semantic CASCADE;
```

### Re-running the installer

The SQL file is written as an extension version script, not as a fully idempotent migration tool.

For the cleanest results:

- run it once in a fresh environment, or
- drop the test database or `semantic` schema before re-installing

### Security and privileges

The installer creates application objects only:

- schemas
- tables
- views
- PL/pgSQL functions

It does not require C compilation or server-side file deployment, which makes it a good fit for managed PostgreSQL environments where custom binary extensions are restricted.

## Summary

On Snowflake Postgres, install `pg_semantic_view` as a SQL bundle by executing:

```bash
psql "host=<host> port=<port> dbname=<database> user=<user> sslmode=require" \
  -v ON_ERROR_STOP=1 \
  -f sql/pg_semantic_view--0.1.0.sql
```

Then use the `semantic.*` APIs directly.

Do not rely on `CREATE EXTENSION pg_semantic_view;` unless Snowflake later adds this prototype to its managed extension catalog.
