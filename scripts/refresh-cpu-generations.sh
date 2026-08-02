#!/usr/bin/env bash
# Check lib/data/cpu-generations.tsv against Intel's and AMD's own sites.
#
#   scripts/refresh-cpu-generations.sh          report only
#   scripts/refresh-cpu-generations.sh --raw    also dump what was scraped
#
# Exits 0 when the table already lists everything the vendors do, 1 when it is behind,
# and 2 when a source could not be read.
#
# **This reports; it does not rewrite the table.** The mapping from a marketing name to
# an ordinal is a judgement — Intel restarted its numbering at "Core Ultra Series 1"
# after 14th Gen, and AMD skips desktop series numbers — and a script that guessed at
# that would put wrong data in front of users with no one having looked at it. What it
# automates is the part that is purely mechanical: noticing that a generation exists
# which the table has never heard of.
#
# Not run in CI. CI has no business depending on two vendors' marketing pages being up,
# and a red build caused by an Akamai hiccup teaches people to ignore red builds. Run it
# when preparing a release, or when someone reports the currency figure looks wrong.

set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
table="$repo/lib/data/cpu-generations.tsv"
raw=0
[ "${1:-}" = --raw ] && raw=1

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# Each vendor blocks the *other* one's user agent, which is worth writing down because
# it looks like a network fault when it happens. Intel's edge returns 403 to a spoofed
# browser UA and 200 to curl's own; AMD's does the reverse. Neither is being evaded —
# these are the plain defaults, one of which each site happens to accept.
readonly UA_BROWSER='Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120 Safari/537.36'

fetch() {
  local url="$1" out="$2" ua="${3:-}"
  local -a args=(-sSL --max-time 30 --retry 2 -o "$out" -w '%{http_code}')
  [ -n "$ua" ] && args+=(-A "$ua")
  curl "${args[@]}" "$url" 2>/dev/null
}

fail() {
  printf 'refresh-cpu-generations: %s\n' "$1" >&2
  exit 2
}

note() { printf '  %s\n' "$1"; }

# --- what the table currently claims -----------------------------------------

table_rows() {
  grep -v -e '^[[:space:]]*#' -e '^[[:space:]]*$' "$table"
}

table_newest() {
  local vendor="$1"
  table_rows | awk -F'\t' -v v="$vendor" '$1 == v && $2+0 > m { m = $2+0; l = $3; y = $4 }
    END { if (l != "") printf "%s|%s|%s", m, l, y }'
}

table_has_label() {
  local vendor="$1" label="$2"
  table_rows | awk -F'\t' -v v="$vendor" -v l="$label" '$1 == v && $3 == l { found = 1 }
    END { exit !found }'
}

# --- Intel -------------------------------------------------------------------
#
# ARK's front page lists every processor family it knows, each linking to a series page
# whose product table carries launch quarters. The family names are the generation
# names, which is exactly the list this table is supposed to mirror.

# ARK writes the same family two ways — "Core Ultra Processors (Series 1)" on one page
# and "Core Ultra Series 3 processors" on another — and neither is what belongs in a
# panel that has forty columns to spend. The table stores the short form, so both
# spellings are folded onto it before comparing.
intel_canonical_name() {
  local n="$1" num
  case "$n" in
    *'Core Ultra'*)
      num="$(printf '%s' "$n" | grep -oE 'Series [0-9]+' | grep -oE '[0-9]+')"
      if [ -n "$num" ]; then
        printf 'Core Ultra Series %s' "$num"
        return 0
      fi
      ;;
  esac
  printf '%s' "$n"
}

intel_report() {
  local code series_path series_id name year earliest
  local behind=0

  code="$(fetch 'https://ark.intel.com' "$work/ark.html")" \
    || fail 'could not reach ark.intel.com'
  [ "$code" = 200 ] || fail "ark.intel.com returned HTTP $code"

  printf 'Intel — from ark.intel.com\n'

  # Series pages for the current consumer line. Older families are numbered "Nth
  # Generation" and are already in the table; what changes is the top of the list.
  while IFS= read -r series_path; do
    [ -n "$series_path" ] || continue
    series_id="${series_path#*/series/}"
    series_id="${series_id%%/*}"

    # The visible name as ARK writes it, taken from the link text.
    name="$(grep -oE "href=\"${series_path//\//\\/}\"[^>]*>[^<]*" "$work/ark.html" 2>/dev/null \
      | head -1 | sed 's/.*>//' | sed 's/Intel® //; s/™//g; s/  */ /g; s/^ *//; s/ *$//')"
    [ -n "$name" ] || continue
    name="$(intel_canonical_name "$name")"

    code="$(fetch "https://www.intel.com$series_path" "$work/s.html")" || continue
    [ "$code" = 200 ] || continue

    # Launch quarters read Q1'26. The earliest across the series is when the generation
    # arrived; later SKUs join it for years afterwards.
    earliest="$(grep -oE "Q[1-4]'[0-9]{2}" "$work/s.html" | sed "s/Q\\([1-4]\\)'\\([0-9][0-9]\\)/\\2\\1/" \
      | sort -n | head -1)"
    [ -n "$earliest" ] || continue
    year="20${earliest:0:2}"

    if table_has_label Intel "$name"; then
      note "have: $name ($year)"
    else
      note "MISSING: $name ($year)"
      behind=1
    fi
  done < <(grep -oE '/content/www/us/en/ark/products/series/[0-9]+/intel-core-ultra[a-z0-9-]*\.html' \
    "$work/ark.html" | sort -u)

  return "$behind"
}

# --- AMD ---------------------------------------------------------------------
#
# AMD has no equivalent index page: the specification browser is a JS application and
# its data endpoint is not documented. What is stable is the desktop Ryzen landing page,
# whose product links carry the series in the path — /ryzen/9000-series/. The highest
# series number there is the newest desktop family.

amd_report() {
  local code highest newest_label newest_ord
  local behind=0

  code="$(fetch 'https://www.amd.com/en/products/processors/desktops/ryzen.html' \
    "$work/ryzen.html" "$UA_BROWSER")" || fail 'could not reach amd.com'
  [ "$code" = 200 ] || fail "amd.com returned HTTP $code"

  printf 'AMD — from amd.com\n'

  highest="$(grep -oE '/ryzen/[0-9]{4}-series/' "$work/ryzen.html" \
    | grep -oE '[0-9]{4}' | sort -n | tail -1)"
  if [ -z "$highest" ]; then
    note 'could not find a desktop series in the page; the layout has changed'
    return 2
  fi

  newest_ord="$(table_newest AMD)"
  newest_label="${newest_ord#*|}"
  newest_label="${newest_label%|*}"

  note "newest desktop series on the site: Ryzen $highest"
  note "newest in the table:               $newest_label"

  case "$newest_label" in
    *"$highest"*) note "table matches" ;;
    *)
      note "MISSING: Ryzen $highest is not the table's newest AMD row"
      behind=1
      ;;
  esac

  # Zen is the generation underneath the series number, and a new one usually shows up
  # in the marketing copy before the series does.
  local zen
  zen="$(grep -oE 'Zen ?[0-9]+' "$work/ryzen.html" | grep -oE '[0-9]+' | sort -n | tail -1)"
  [ -n "$zen" ] && note "highest Zen generation named on the page: Zen $zen"

  return "$behind"
}

# --- report ------------------------------------------------------------------

[ -r "$table" ] || fail "cannot read $table"

printf 'Checking %s\n' "${table#"$repo"/}"
printf 'Table says it was verified: %s\n\n' \
  "$(grep -oE 'Verified against vendor sites: [0-9-]+' "$table" || printf '(no verification line)')"

status=0
intel_report || status=1
printf '\n'
amd_report || status=1

printf '\n'
if [ "$status" -eq 0 ]; then
  printf 'Table is current. Update the verification date in %s.\n' "${table#"$repo"/}"
else
  printf 'Table is behind. Add the MISSING rows above, then bump the verification date.\n'
  printf 'The ordinal is a judgement, not a scrape: it is the position in the release\n'
  printf 'sequence, which is why this script will not write the row for you.\n'
fi

if [ "$raw" -eq 1 ]; then
  printf '\n--- raw ---\n'
  grep -oE 'Core™? Ultra[^<"&]{0,30}' "$work/ark.html" | sort -u
  grep -oE '/ryzen/[0-9]{4}-series/' "$work/ryzen.html" | sort -u
fi

exit "$status"
