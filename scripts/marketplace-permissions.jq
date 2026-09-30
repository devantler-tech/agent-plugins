# Bind native repository identity to a successful nonpersistent notes response.
# GitHub requires contents-write for generation, but creates no remote object.
def native_writer_repository($repo;$branch;$node;$proof):
  type=="object" and .full_name==$repo and .node_id==$node and
  (.id|type=="number" and .>0 and floor==.) and .archived==false and
  .default_branch==$branch and
  ($proof | type=="object" and (.name|type=="string" and length>0) and (.body|type=="string"));

# The native capability proof is required for a user role or an explicit null App role.
def compatible_user_role:
  has("viewerPermission") and (.viewerPermission | .==null or .=="ADMIN" or .=="MAINTAIN" or .=="WRITE");
