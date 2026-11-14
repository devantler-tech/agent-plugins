# Canonical stable version predicates shared by the manifest validator and the cache-version tools.
def stable_syntax:
  type == "string" and test("\\A(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)\\z");
def stable_version: stable_syntax and (split(".") | all(.[]; length <= 9));
