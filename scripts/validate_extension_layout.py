from __future__ import annotations

import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CONTROL = ROOT / "pg_semantic_view.control"
SQL_FILE = ROOT / "sql" / "pg_semantic_view--0.1.0.sql"
README = ROOT / "README.md"
DEMO = ROOT / "examples" / "demo.sql"


def require(path: Path) -> None:
    if not path.exists():
        raise SystemExit(f"missing required file: {path}")


def require_contains(text: str, needle: str, label: str) -> None:
    if needle not in text:
        raise SystemExit(f"missing {label}: {needle}")


def main() -> None:
    for path in (CONTROL, SQL_FILE, README, DEMO):
        require(path)

    control_text = CONTROL.read_text()
    sql_text = SQL_FILE.read_text()
    demo_text = DEMO.read_text()

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
        "CREATE OR REPLACE FUNCTION semantic.export_osi(",
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

    print("extension layout validation passed")


if __name__ == "__main__":
    main()
