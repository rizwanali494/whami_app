#!/usr/bin/env bash
# Packages a region_packs/<packId>/ folder into a .whami zip ready for
# upload to Firebase Storage, and prints a catalog.json entry with the
# real sha256 checksum and size to paste in.
#
# Usage: scripts/package_region_pack.sh <packId>
# Example: scripts/package_region_pack.sh usa_california

set -euo pipefail

PACK_ID="${1:-}"
if [[ -z "$PACK_ID" ]]; then
  echo "Usage: $0 <packId>" >&2
  echo "Example: $0 usa_california" >&2
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACK_DIR="$ROOT_DIR/region_packs/$PACK_ID"
OUT_DIR="$ROOT_DIR/build/packs"
OUT_FILE="$OUT_DIR/$PACK_ID.whami"

if [[ ! -d "$PACK_DIR" ]]; then
  echo "Pack folder not found: $PACK_DIR" >&2
  exit 1
fi

for required in metadata.json landmarks.sqlite map.mbtiles; do
  if [[ ! -f "$PACK_DIR/$required" ]]; then
    echo "Missing required file: $PACK_DIR/$required" >&2
    exit 1
  fi
done

mkdir -p "$OUT_DIR"
rm -f "$OUT_FILE"

echo "Zipping $PACK_DIR -> $OUT_FILE ..."
(cd "$PACK_DIR" && zip -X -r "$OUT_FILE" . -x '.*')

CHECKSUM=$(shasum -a 256 "$OUT_FILE" | awk '{print $1}')
SIZE_BYTES=$(stat -f%z "$OUT_FILE" 2>/dev/null || stat -c%s "$OUT_FILE")

echo
echo "Done. Upload $OUT_FILE to Firebase Storage, then paste this into assets/catalog.json:"
echo
cat <<EOF
{
  "id": "$PACK_ID",
  "downloadUrl": "<paste Firebase Storage download URL here>",
  "checksum": "$CHECKSUM",
  "sizeBytes": $SIZE_BYTES
}
EOF
