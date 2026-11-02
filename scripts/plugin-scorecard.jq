# Reporting only. Evidence never supplies executable instructions or output paths.
def require($ok): if $ok then . else error("invalid evidence") end;
def utc:
  . as $s | require(type=="string" and test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\\.[0-9]{1,9})?Z$")) |
  sub("\\.[0-9]+Z$";"Z") as $whole | ($whole|fromdateiso8601) as $epoch |
  require(($epoch|todateiso8601)==$whole) |
  $s | capture("^(?<base>[^.]+?)(?:\\.(?<fraction>[0-9]+))?Z$") |
  .base+"."+(((.fraction // "")+"000000000")[0:9])+"Z";
def version: type=="string" and test("^(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)$");
def array_or_empty:
  if .==null then [] else require(type=="array") end;
def attrs:
  array_or_empty | require(all(.[];type=="object" and (.key|type)=="string" and (.value|type)=="object")) |
  require((map(.key)|unique|length)==length) |
  map({key,value:(.value.stringValue // .value.intValue // .value.boolValue // .value.doubleValue)}) | from_entries;
def events:
  .resourceLogs | array_or_empty | .[] | require(type=="object") |
  (.resource.attributes|attrs|."service.name") as $service |
  .scopeLogs | array_or_empty | .[] | require(type=="object") |
  .logRecords | array_or_empty | .[] | require(type=="object") |
  select($service=="claude-code" or $service=="claude-code-desktop") |
  (.attributes | attrs) |
  select(."event.name"=="plugin_loaded" or ."event.name"=="skill_activated") |
  {producer:$service,kind:."event.name",at:(."event.timestamp"|utc),
    sequence:(."event.sequence"|tonumber),session:."session.id",
    plugin:."plugin.name",marketplace:."marketplace.name",version:."plugin.version",
    skill:."skill.name",source:."skill.source",safe_mode:.safe_mode} |
  require((.session|type)=="string" and (.session|length)>0 and .sequence>=0 and (.sequence|floor)==.sequence);
def percent: if .total>0 then 100*.passed/.total else null end;
def grade:
  require((.result.passed|type)=="number" and (.result.total|type)=="number" and
    .result.total>0 and .result.passed>=0 and .result.passed<=.result.total and
    (.result.passed|floor)==.result.passed and (.result.total|floor)==.result.total and
    (.result.pass_rate|type)=="number") |
  require(((.result.pass_rate-(.result.passed/.result.total))|fabs)<=0.0051) |
  require((.eval_id|type)=="number" and (.eval_id|floor)==.eval_id and
    (.run_number|type)=="number" and .run_number>=1 and (.run_number|floor)==.run_number) |
  if has("expectations") then
    require((.expectations|type)=="array" and (.expectations|length)==.result.total and
      all(.expectations[];(.text|type)=="string" and (.passed|type)=="boolean")) |
    require(([.expectations[]|select(.passed)]|length)==.result.passed and
      (.expectations|map(.text)|unique|length)==.result.total)
  else . end;
def totals:
  {runs:length,passed:(map(.result.passed)|add),total:(map(.result.total)|add)} |
  . + {percent:percent};
def benchmark:
  . as $b | .data | (.metadata.timestamp|utc) as $timestamp |
  require((.runs|type)=="array" and (.runs|length)>0) |
  [.runs[]|require(.configuration=="with_skill" or .configuration=="without_skill")|grade] as $runs |
  require(($runs|map([.configuration,.eval_id,.run_number])|unique|length)==($runs|length)) |
  [$runs[]|select(.configuration=="with_skill")]| require(length>0) | . as $with |
  [$runs[]|select(.configuration=="without_skill")] as $without |
  ($with|totals) as $w | (if ($without|length)>0 then $without|totals else null end) as $base |
  ([$with[]|[.eval_id,.run_number,.result.total,((.expectations // [])|map(.text)|sort)]]|sort) as $wk |
  ([$without[]|[.eval_id,.run_number,.result.total,((.expectations // [])|map(.text)|sort)]]|sort) as $bk |
  {plugin:$b.plugin,declared_version:$b.version,skill:$b.data.metadata.skill_name,
    timestamp:$timestamp,with_skill:$w,without_skill:$base,
    baseline_delta_pp:(if $base!=null and $wk==$bk and all($runs[];has("expectations")) then $w.percent-$base.percent else null end)};

$catalogue[0] | require((.name|type)=="string" and (.plugins|type)=="array") | . as $c |
require((.plugins|map(.name)|unique|length)==(.plugins|length)) |
([$usage[]|events]|unique) as $events |
# Conflicting replays cannot be silently resolved by latest-wins parsing.
require(all(($events|group_by([.producer,.session,.at,.sequence,.kind]))[];length==1)) |
(if ($usage|length)>0 then
  ($since|utc) as $start | ($until|utc) as $end | require($start<$end) | {start:$start,end:$end}
 else null end) as $window |
[$events[]|select(.at>=$window.start and .at<$window.end)] as $observed |
[$observed[]|select(.kind=="plugin_loaded")] as $loads |
# Activation events identify their owner directly. Inventory cannot attest a call's version.
[$observed[]|select(.kind=="skill_activated" and (.source=="plugin" or .source==null))] as $activations |
[$activations[]|select(.marketplace==$c.name and .source=="plugin")|
  . as $a|select(any($c.plugins[];.name==$a.plugin))] as $owned |
[$activations[]|select(.marketplace==null or .marketplace=="third-party" or
  (.marketplace==$c.name and (.source==null or (.plugin as $p|all($c.plugins[];.name!=$p)))))] as $unattributed |
[$benchmarks[]|benchmark] as $scores |
require(($scores|map([.plugin,.declared_version,.skill])|unique|length)==($scores|length)) |
require(all($scores[];.plugin as $p|any($c.plugins[];.name==$p))) |
{window:(if $window!=null then {since:$since,until:$until} else null end),
 coverage:{status:(if ($observed|length)>0 then "OBSERVED_ONLY" else "UNKNOWN" end),
   runtime:"claude-code",export_files:($usage|length),
   unattributed_activations:($unattributed|length),activation_versions:"UNKNOWN",
   other_runtimes:"UNKNOWN",components:"skill activations only; agents, hooks and MCP use are unmeasured"},
 plugins:[$c.plugins[] | . as $p |
   [$loads[]|select(.plugin==$p.name and .marketplace==$c.name)] as $inventory |
   [$owned[]|select(.plugin==$p.name)] as $uses |
   {name:.name,catalogue_version:.version,
    usage:{activations:(if ($uses|length)>0 then $uses|length elif ($inventory|length)>0 and ($unattributed|length)==0 then 0 else null end),
      loaded_versions:([$inventory[].version|select(version)]|unique),
      configured_sessions:(if ($inventory|length)>0 then [$inventory[]|[.producer,.session]]|unique|length else null end),
      sessions:(if ($uses|length)>0 then [$uses[]|[.producer,.session]]|unique|length else null end)},
    benchmarks:[$scores[]|select(.plugin==$p.name)]}]}
