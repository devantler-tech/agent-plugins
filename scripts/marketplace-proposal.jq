# Complete repository-bound observations; content fields are compared only as data.
include "marketplace-release";
def proposal_snapshot($repo;$source;$baseline;$tags;$permission;$branch;$owned):
  . as $pages |
  if ($permission|length)!=1 or
     ($permission[0] | type!="object" or .full_name!=$repo or .archived!=false or
       .default_branch!="main" or (.id|type!="number" or .<=0 or floor!=.) or (.node_id|nonblank|not)) or
     type!="array" or length==0 then error("repository identity or page stream is incomplete") else . end |
  if all(.[]; .errors==null and (.data.repository |
    type=="object" and .id==$permission[0].node_id and .nameWithOwner==$repo and .isArchived==false and
    .defaultBranchRef.name=="main" and .defaultBranchRef.target.__typename=="Commit" and
    .defaultBranchRef.target.oid==$source and
    (.baseline | type=="object" and (.databaseId|type=="number" and .>0 and floor==.) and .tagName==$baseline.tag and
      .isDraft==false and .isPrerelease==false and (.publishedAt|nonblank) and .tagCommit.oid==$baseline.commit) and
    .baseline==$pages[0].data.repository.baseline and
    has("candidate") and .candidate==null and has("proposal") and
    (if $owned=="" then .proposal==null else
      .proposal.name==$branch and .proposal.target.__typename=="Commit" and .proposal.target.oid==$owned end) and
    (.pullRequests | type=="object" and (.totalCount|type=="number" and .>=0 and floor==.) and
      (.nodes|type=="array") and .totalCount==(.nodes|length) and
      all(.nodes[]; (.number|type=="number" and .>0 and floor==.) and (.headRefName|nonblank) and
        (.files | type=="object" and (.totalCount|type=="number" and .>=0 and floor==.) and
          (.nodes|type=="array") and .totalCount==(.nodes|length) and all(.nodes[]; (.path|nonblank))) and
        (.headRefName|startswith("automation/marketplace-v")|not) and
        all(.files.nodes[]; .path!=".github/plugin/marketplace.json" and .path!=".claude-plugin/marketplace.json")))))
    then . else error("main, baseline, occupancy or complete PR visibility is invalid") end |
  if all(range(0;length); . as $i | $pages[$i].data.repository.refs |
    type=="object" and (.totalCount|type=="number" and .>=0 and floor==.) and .totalCount==$pages[0].data.repository.refs.totalCount and
    (.nodes|type=="array" and length<=100) and
    all(.nodes[]; (.name|nonblank) and (.target.__typename=="Commit" or .target.__typename=="Tag") and
      (.target.oid|type=="string" and test("^[0-9a-f]{40}$"))) and
    .pageInfo.hasNextPage==($i<($pages|length)-1) and
    (if $i<($pages|length)-1 then (.pageInfo.endCursor|nonblank) else true end)) then .
    else error("tag pagination or identities are incomplete") end |
  ([.[].data.repository.refs.nodes[]|{name,oid:.target.oid}]|sort_by(.name)) as $remote |
  if ($remote|length)!=$pages[0].data.repository.refs.totalCount or
     ($remote|map(.name)|unique|length)!=($remote|length) or $remote!=$tags
    then error("local and complete remote tag objects differ") else . end |
  {repository:$repo,repositoryId:$permission[0].node_id,repositoryDatabaseId:$permission[0].id,
   sourceCommit:$source,baseline:$baseline,publishedBaseline:$pages[0].data.repository.baseline,tags:$remote};

# A draft readback binds the mutable PR projection to the exact signed, reproduced commit.
def proposal_readback($repo;$node;$source;$branch;$commit;$number;$title;$body):
  .errors==null and (.data.repository |
    .id==$node and .nameWithOwner==$repo and .isArchived==false and
    .defaultBranchRef.name=="main" and .defaultBranchRef.target.oid==$source and
    .ref.name==$branch and .ref.target.oid==$commit and
    (.pullRequest | .number==$number and .state=="OPEN" and .isDraft==true and
      .author.login=="github-actions[bot]" and
      .headRefName==$branch and .headRefOid==$commit and .baseRefName=="main" and .baseRefOid==$source and
      .headRepository.nameWithOwner==$repo and .title==$title and .body==$body and
      .url==("https://github.com/"+$repo+"/pull/"+($number|tostring))));
