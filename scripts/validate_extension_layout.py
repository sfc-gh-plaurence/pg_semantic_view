from __future__ import annotations

import re
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CONTROL = ROOT / "pg_semantic_view.control"
SQL_FILE = ROOT / "sql" / "pg_semantic_view--0.1.0.sql"
README = ROOT / "README.md"
DEMO = ROOT / "examples" / "demo.sql"
SNOWFLAKE_DEMO = ROOT / "examples" / "demo_snowflake_postgres.sql"
SNOWFLAKE_INSTALL_DOC = ROOT / "docs" / "installing-on-snowflake-postgres.md"
SAMPLE_DATA_DOC = ROOT / "docs" / "using-sample-data-in-postgres.md"
SNOWFLAKE_IMPORT_DOC = ROOT / "docs" / "importing-snowflake-semantic-json.md"
SNOWFLAKE_JSON_EXAMPLE = ROOT / "examples" / "snowflake_semantic_view_tpcds.json"
SNOWFLAKE_IMPORT_SQL = ROOT / "examples" / "import_snowflake_semantic_view.sql"


def require(path: Path) -> None:
    if not path.exists():
        raise SystemExit(f"missing required file: {path}")


def require_contains(text: str, needle: str, label: str) -> None:
    if needle not in text:
        raise SystemExit(f"missing {label}: {needle}")


def main() -> None:
    for path in (
        CONTROL,
        SQL_FILE,
        README,
        DEMO,
        SNOWFLAKE_DEMO,
        SNOWFLAKE_INSTALL_DOC,
        SAMPLE_DATA_DOC,
        SNOWFLAKE_IMPORT_DOC,
        SNOWFLAKE_JSON_EXAMPLE,
        SNOWFLAKE_IMPORT_SQL,
    ):
        require(path)

    control_text = CONTROL.read_text()
    sql_text = SQL_FILE.read_text()
    demo_text = DEMO.read_text()
    snowflake_demo_text = SNOWFLAKE_DEMO.read_text()
    install_doc_text = SNOWFLAKE_INSTALL_DOC.read_text()
    sample_data_doc_text = SAMPLE_DATA_DOC.read_text()
    snowflake_import_doc_text = SNOWFLAKE_IMPORT_DOC.read_text()
    snowflake_json_example_text = SNOWFLAKE_JSON_EXAMPLE.read_text()
    snowflake_import_sql_text = SNOWFLAKE_IMPORT_SQL.read_text()

    require_contains(control_text, "default_version = '0.1.0'", "control file version")
    require_contains(sql_text, "CREATE SCHEMA IF NOT EXISTS semantic;", "semantic schema declaration")

    expected_objects = [
        "CREATE TABLE semantic.views",
        "CREATE TABLE semantic.logical_tables",
        "CREATE TABLE semantic.relationships",
        "CREATE TABLE semantic.dimensions",
        "CREATE TABLE semantic.facts",
        "CREATE TABLE semantic.metrics",
        "CREATE TABLE semantic.metric_dependencies",
        "CREATE TABLE semantic.examples",
        "CREATE OR REPLACE FUNCTION semantic.create_view(",
        "CREATE OR REPLACE FUNCTION semantic.compile_sql(",
        "CREATE OR REPLACE FUNCTION semantic.query(",
        "CREATE OR REPLACE FUNCTION semantic.import_osi(",
        "CREATE OR REPLACE FUNCTION semantic.import_snowflake_view(",
        "CREATE OR REPLACE FUNCTION semantic.export_osi(",
        "CREATE OR REPLACE FUNCTION semantic.build_qualified_name(",
        "CREATE OR REPLACE FUNCTION semantic.resolve_metric_id(",
        "CREATE VIEW semantic.meta_views AS",
        "CREATE VIEW semantic.meta_metrics AS",
    ]

    for expected in expected_objects:
        require_contains(sql_text, expected, "expected SQL object")

    function_delimiter_count = len(re.findall(r"\$function\$", sql_text))
    if function_delimiter_count % 2 != 0:
        raise SystemExit("unbalanced $function$ delimiters in SQL file")

    if "SELECT semantic.create_view(" not in demo_text or "SELECT semantic.compile_sql(" not in demo_text:
        raise SystemExit("demo.sql does not exercise the prototype entry points")

    if re.search(r"(?mi)^\s*CREATE EXTENSION\s+pg_semantic_view\s*;", snowflake_demo_text):
        raise SystemExit("Snowflake demo should not use CREATE EXTENSION pg_semantic_view")

    require_contains(install_doc_text, "sql/pg_semantic_view--0.1.0.sql", "Snowflake install SQL path")
    require_contains(install_doc_text, "examples/demo_snowflake_postgres.sql", "Snowflake demo reference")
    require_contains(
        sample_data_doc_text,
        "https://medium.com/snowflake/getting-started-with-snowflake-semantic-view-7eced29abe6f",
        "original Snowflake sample-data reference",
    )
    require_contains(sample_data_doc_text, "tpcds_semantic_view_sm", "sample data semantic view name")
    require_contains(sample_data_doc_text, "semantic.create_view(", "sample data semantic registration example")
    require_contains(sample_data_doc_text, "semantic.query(", "sample data semantic query example")
    require_contains(
        snowflake_import_doc_text,
        "semantic.import_snowflake_view(",
        "Snowflake import function documentation",
    )
    require_contains(
        snowflake_import_doc_text,
        "examples/snowflake_semantic_view_tpcds.json",
        "Snowflake JSON example reference",
    )
    require_contains(
        snowflake_import_sql_text,
        "semantic.import_snowflake_view(",
        "Snowflake import SQL example",
    )

    parsed_json_example = json.loads(snowflake_json_example_text)
    for required_key in ("tables", "relationships", "facts", "dimensions", "metrics", "ai_verified_queries"):
        if required_key not in parsed_json_example:
            raise SystemExit(f"Snowflake JSON example missing key: {required_key}")

    print("extension layout validation passed")


if __name__ == "__main__":
    main()
