# Importing Snowflake-shaped semantic JSON into PostgreSQL

This guide explains how to use `semantic.import_snowflake_view(...)` with the current SQL-first prototype.

It is intended for cases where you want to:

- preserve Snowflake-style semantic names such as `Item.Brand`
- preserve a Snowflake-like semantic model layout in JSON
- import that model into PostgreSQL or Snowflake Postgres
- run equivalent queries through the prototype without manually rewriting every object into `semantic.create_view(...)`

## What this import path expects

The `semantic.import_snowflake_view(...)` function accepts a JSONB document with Snowflake-shaped sections such as:

- `tables`
- `relationships`
- `facts`
- `dimensions`
- `metrics`
- `ai_verified_queries`

The importer translates that JSON into the prototype's normalized catalog tables and then delegates to `semantic.create_view(...)`.

## Important limitation

This is a **Snowflake-shaped JSON import helper**, not a parser for raw Snowflake SQL DDL.

That means the current prototype does **not** accept this directly:

```sql
CREATE SEMANTIC VIEW ...
```

Instead, you must first provide a JSON representation of the model.

## Files included in this repository

This repository now includes two stronger reference artifacts:

- [`examples/snowflake_semantic_view_tpcds.json`](../examples/snowflake_semantic_view_tpcds.json)
  - a Snowflake-shaped JSON semantic model using the same TPC-DS-style subset described in the sample-data guide
- [`examples/import_snowflake_semantic_view.sql`](../examples/import_snowflake_semantic_view.sql)
  - a runnable SQL script that imports the JSON model and compiles a derived-metric query

These examples are meant to be used together with:

- [`docs/using-sample-data-in-postgres.md`](using-sample-data-in-postgres.md)

## Recommended workflow

### Step 1: install the prototype

If you are using standard PostgreSQL:

```sql
CREATE EXTENSION pg_semantic_view;
```

If you are using Snowflake Postgres, follow:

- [`docs/installing-on-snowflake-postgres.md`](installing-on-snowflake-postgres.md)

### Step 2: create the physical sample tables

Use the schema and sample rows from:

- [`docs/using-sample-data-in-postgres.md`](using-sample-data-in-postgres.md)

The import example assumes these physical tables already exist:

- `public.store_sales`
- `public.item`
- `public.date_dim`
- `public.store`

### Step 3: review the JSON structure

Open:

- [`examples/snowflake_semantic_view_tpcds.json`](../examples/snowflake_semantic_view_tpcds.json)

The example demonstrates:

- Snowflake-style qualified names
  - `Item.Brand`
  - `Date.Year`
  - `StoreSales.TotalSalesQuantity`
- structured relationship metadata
  - `from_columns`
  - `to_columns`
- fact, dimension, and metric definitions
- AI instructions
  - `ai_sql_generation`
  - `ai_question_categorization`
- verified query metadata
  - `ai_verified_queries`
- a derived metric
  - `StoreSales.TotalSalesQuantityRounded`

## Example JSON shape

At a high level, the importer expects a structure like:

```json
{
  "name": "TPCDS_SEMANTIC_VIEW_SM",
  "comment": "TPC-DS-style semantic view example",
  "tables": [],
  "relationships": [],
  "facts": [],
  "dimensions": [],
  "metrics": [],
  "ai_verified_queries": []
}
```

## Step 4: import the model

You can run the included SQL script:

```bash
psql -v ON_ERROR_STOP=1 -f examples/import_snowflake_semantic_view.sql
```

Or you can call the function directly:

```sql
SELECT semantic.import_snowflake_view(
    p_view_name => 'tpcds_semantic_view_sm',
    p_document => $json$
    {
      "name": "TPCDS_SEMANTIC_VIEW_SM",
      "comment": "TPC-DS-style semantic view example",
      "tables": [],
      "relationships": [],
      "facts": [],
      "dimensions": [],
      "metrics": [],
      "ai_verified_queries": []
    }
    $json$::jsonb
);
```

## Step 5: inspect the imported semantic metadata

After import, verify the resulting objects:

```sql
SELECT * FROM semantic.meta_views WHERE view_name = 'tpcds_semantic_view_sm';
SELECT * FROM semantic.meta_relationships WHERE view_name = 'tpcds_semantic_view_sm';
SELECT * FROM semantic.meta_dimensions WHERE view_name = 'tpcds_semantic_view_sm';
SELECT * FROM semantic.meta_facts WHERE view_name = 'tpcds_semantic_view_sm';
SELECT * FROM semantic.meta_metrics WHERE view_name = 'tpcds_semantic_view_sm';
SELECT * FROM semantic.meta_examples WHERE view_name = 'tpcds_semantic_view_sm';
```

The imported model should preserve:

- qualified names
- verified query metadata
- SQL-generation and question-categorization guidance
- structured relationship metadata

## Step 6: compile and run a Snowflake-style query pattern

Because the prototype now resolves qualified names, you can query using identifiers that are much closer to the original Snowflake example:

```sql
SELECT semantic.compile_sql(
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
);
```

You can also query the imported derived metric:

```sql
SELECT *
FROM semantic.query(
    p_semantic_view => 'tpcds_semantic_view_sm',
    p_metrics => ARRAY['StoreSales.TotalSalesQuantityRounded'],
    p_dimensions => ARRAY['Item.Brand', 'Store.State'],
    p_filters => '{
      "Date.Year":{"eq":"2002"},
      "Date.Month":{"eq":"12"}
    }'::jsonb
) AS t(
    item_brand text,
    store_state text,
    total_sales_quantity_rounded numeric
);
```

## Mapping notes

The importer maps Snowflake-shaped JSON into the prototype as follows:

- `tables` -> logical tables
- `relationships` -> relationships
- `facts` -> facts
- `dimensions` -> dimensions
- `metrics` -> metrics
- `ai_verified_queries` -> examples / verified-query metadata

It also preserves:

- qualified names
- structured join-column metadata
- AI guidance fields
- extension metadata

## Best practices

### Prefer qualified names in imported models

When importing Snowflake-shaped JSON, include fields like:

- `qualified_name: "Item.Brand"`
- `qualified_name: "StoreSales.TotalSalesQuantity"`

This makes later query translation much cleaner.

### Prefer structured relationship columns when available

If you know the relationship keys, provide:

- `from_columns`
- `to_columns`

The importer can use these to build a join expression when raw `join_sql` is absent.

### Keep SQL expressions PostgreSQL-compatible

The current importer stores and compiles SQL expressions as PostgreSQL SQL. If your Snowflake expressions rely on dialect-specific functions, you may need to translate them before import.

## Comparison to the original Snowflake example

This workflow is designed to support side-by-side comparison with:

- Chanin Nantasenamat, **"Getting Started with Snowflake Semantic View"**
  - https://medium.com/snowflake/getting-started-with-snowflake-semantic-view-7eced29abe6f

The prototype does not reproduce Snowflake's native `CREATE SEMANTIC VIEW` or `SEMANTIC_VIEW(...)` syntax, but it now preserves much more of the original semantic structure and naming when importing a Snowflake-shaped definition.
