"""Simple parse check for the Phase-01 SQL migration using sqlite3 parser."""

from pathlib import Path
import sqlite3

sql_file = Path(__file__).resolve().parents[1] / "database" / "migrations" / "2026_03_01_000000_create_foundation_tables.sql"
script = sql_file.read_text(encoding="utf-8")

conn = sqlite3.connect(":memory:")
try:
    conn.executescript(script)
finally:
    conn.close()

print("SQL parse check passed")
