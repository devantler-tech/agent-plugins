# Normalize a complete paginated GitHub observation; absence is meaningful only in valid data.
include "marketplace-permissions";
def oid: type == "string" and test("^[0-9a-f]{40}$");
def nonempty: type == "string" and length > 0;
def require($condition; $message): if $condition then . else error($message) end;
require(type == "array" and length > 0; "missing remote pages")
| . as $pages
| require(all(.[];
    (.errors // []) == [] and
    (.data.repository | type == "object" and
      .nameWithOwner == $repo and .isArchived == false and
      (.id | nonempty) and compatible_user_role and
      (. as $repository | ($permission | length)==1 and
        ($permission[0] | native_writer_repository($repo;$repository.defaultBranchRef.name;$repository.id))) and
      (.defaultBranchRef | type == "object" and (.name | nonempty) and
        .target.__typename == "Commit" and (.target.oid | oid) and .target.oid == $release) and
      has("release") and .release == null and
      (.refs | type == "object" and
        (.totalCount | type == "number" and . >= 0 and floor == .) and
        (.nodes | type == "array" and length <= 100) and
        (.pageInfo | type == "object" and (.hasNextPage | type == "boolean") and
          has("endCursor") and (.endCursor == null or (.endCursor | nonempty))) and
        all(.nodes[]; (.name | nonempty) and (.target.oid | oid) and
          (.target.__typename | . == "Commit" or . == "Tag" or . == "Tree" or . == "Blob")))));
    "remote identity, release, branch, or tag response is invalid")
| require(all(range(0; length); . as $i |
    $pages[$i].data.repository.refs.pageInfo.hasNextPage == ($i < ($pages | length) - 1) and
    (if $i < ($pages | length) - 1 then
      ($pages[$i].data.repository.refs.pageInfo.endCursor | nonempty) and
      ($pages[$i].data.repository.refs.nodes | length > 0)
    else true end)); "incomplete pagination")
| require(([.[].data.repository.refs.pageInfo.endCursor | select(. != null)] | length) ==
    ([.[].data.repository.refs.pageInfo.endCursor | select(. != null)] | unique | length);
    "repeated pagination cursor")
| require(([.[].data.repository | {id,nameWithOwner,isArchived,viewerPermission,defaultBranchRef,release}] | unique | length) == 1;
    "repository changed across pages")
| require(([.[].data.repository.refs.totalCount] | unique | length) == 1; "tag count changed across pages")
| [.[].data.repository.refs.nodes[] | {name,oid:.target.oid}] | sort_by(.name)
| require(length == $pages[0].data.repository.refs.totalCount; "incomplete tag inventory")
| require(length == ([.[].name] | unique | length); "duplicate tag")
| {repository:$repo,repositoryId:$pages[0].data.repository.id,defaultBranch:$pages[0].data.repository.defaultBranchRef.name,
   releaseCommit:$release,tags:.,candidateRelease:"ABSENT"}
