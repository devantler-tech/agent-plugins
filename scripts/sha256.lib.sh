# shellcheck shell=bash
# Digest helpers shared by the desired-state validator and its generator.
#
# The generator writes exactly what the validator checks, so the two must hash a file
# identically. Sourcing one definition is what makes that true by construction: a
# second copy could drift silently, and the only symptom would be a required check
# that no amount of regeneration can satisfy.

# Hash definition-file bytes after normalizing checkout-only CRLF pairs to committed LF
# bytes. Clear inherited Perl I/O controls and set both stream handles to raw bytes
# explicitly. This preserves invalid UTF-8, NULs, lone CRs, and a missing final newline
# instead of decoding or reconstructing the file as text.
sha256_file() {
  if command -v sha256sum > /dev/null 2>&1; then
    LC_ALL=C PERL5OPT='' PERL_UNICODE='' PERLIO='' perl -C0 -pe \
      'BEGIN { binmode STDIN, ":raw"; binmode STDOUT, ":raw" } s/\r\n/\n/g' \
      < "$1" | sha256sum | awk '{ print $1 }'
  else
    LC_ALL=C PERL5OPT='' PERL_UNICODE='' PERLIO='' perl -C0 -pe \
      'BEGIN { binmode STDIN, ":raw"; binmode STDOUT, ":raw" } s/\r\n/\n/g' \
      < "$1" | shasum -a 256 | awk '{ print $1 }'
  fi
}

# Hash the exact bytes of an executable runtime asset. Unlike definition files,
# runtime assets are executed from the checkout, so checkout-only CRLF changes
# must invalidate the declared digest instead of being normalized away.
sha256_bytes() {
  if command -v sha256sum > /dev/null 2>&1; then
    sha256sum "$1" | awk '{ print $1 }'
  else
    shasum -a 256 "$1" | awk '{ print $1 }'
  fi
}
