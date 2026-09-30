# REST exposes effective repository permissions for users and installation tokens.
# A null GraphQL user role is never permission evidence by itself.
def native_writer_repository($repo;$branch;$node):
  type=="object" and .full_name==$repo and .node_id==$node and
  (.id|type=="number" and .>0 and floor==.) and .archived==false and
  .default_branch==$branch and (.permissions|type=="object" and .push==true and .pull==true);

def compatible_user_role:
  has("viewerPermission") and (.viewerPermission | .==null or .=="ADMIN" or .=="MAINTAIN" or .=="WRITE");
