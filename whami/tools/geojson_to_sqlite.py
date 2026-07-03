import json
import sqlite3
import uuid
import sys
import os

if len(sys.argv) != 3:
    print("Usage:")
    print("python3 geojson_to_sqlite.py <input.geojson> <output.sqlite>")
    sys.exit(1)

input_file = sys.argv[1]
output_file = sys.argv[2]

if not os.path.exists(input_file):
    print(f"Input file not found: {input_file}")
    sys.exit(1)

with open(input_file, "r", encoding="utf-8") as f:
    geojson = json.load(f)

conn = sqlite3.connect(output_file)
cursor = conn.cursor()

cursor.execute("""
CREATE TABLE IF NOT EXISTS landmarks (
    id TEXT PRIMARY KEY,
    name TEXT,
    category TEXT,
    latitude REAL,
    longitude REAL,
    description TEXT,
    source TEXT,
    verified INTEGER,
    confidence REAL
)
""")

count = 0

for feature in geojson.get("features", []):

    geometry = feature.get("geometry")

    if geometry is None:
        continue

    if geometry.get("type") != "Point":
        continue

    coordinates = geometry.get("coordinates", [])

    if len(coordinates) != 2:
        continue

    lon = coordinates[0]
    lat = coordinates[1]

    props = feature.get("properties", {})

    name = props.get("name", "")

    category = (
        props.get("amenity")
        or props.get("tourism")
        or props.get("natural")
        or props.get("man_made")
        or props.get("historic")
        or props.get("aeroway")
        or props.get("railway")
        or props.get("highway")
        or "unknown"
    )

    cursor.execute("""
        INSERT INTO landmarks
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    """, (
        str(uuid.uuid4()),
        name,
        category,
        lat,
        lon,
        "",
        "SYSTEM",
        1,
        1.0,
    ))

    count += 1

conn.commit()
conn.close()

print("--------------------------------")
print(f"Imported {count} landmarks")
print(f"Database saved to:")
print(output_file)
print("--------------------------------")