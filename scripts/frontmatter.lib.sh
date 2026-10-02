#!/usr/bin/env bash
# Shared minimum header observation; never examine instruction bodies for metadata.
FRONTMATTER_PARSER="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/frontmatter.awk"
frontmatter_has_value() {
  awk -v mode=text -v field="$2" -f "$FRONTMATTER_PARSER" "$1"
}
frontmatter_repository() {
  awk -v mode=repository -f "$FRONTMATTER_PARSER"
}
