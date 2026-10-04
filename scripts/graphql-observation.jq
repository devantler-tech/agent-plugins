# A successful GraphQL envelope is an object with no errors field or exactly [].
def graphql_complete:
  if type != "object" then false
  else ((has("errors") | not) or .errors == []) end;
