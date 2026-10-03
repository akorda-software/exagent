Code.require_file(Path.expand("opik_profile.exs", __DIR__))
alias OpikAcceptance.Profile

attribute = fn key, type, value -> %{key: key, value: %{value: {type, value}}} end

attrs = [
  attribute.("exagent.operation", :string_value, "model"),
  attribute.("exagent.cost.cents", :double_value, 0.03),
  attribute.("exagent.cost.quality", :string_value, "estimated"),
  attribute.("test.false", :bool_value, false),
  attribute.("test.count", :int_value, 0),
  attribute.("gen_ai.request.model", :string_value, "test"),
  attribute.("gen_ai.usage.input_tokens", :int_value, 3)
]

span = %{
  trace_id: <<1::128>>,
  span_id: <<2::64>>,
  parent_span_id: <<>>,
  name: "native-name",
  status: %{code: :STATUS_CODE_ERROR},
  start_time_unix_nano: 42,
  end_time_unix_nano: 84,
  events: [],
  attributes: attrs
}

request = %{
  resource_spans: [
    %{
      resource: %{attributes: [attribute.("test.false", :bool_value, false)]},
      scope_spans: [%{scope: %{name: "native-scope"}, spans: [span]}]
    }
  ]
}

projected = Profile.project(request)
[resource] = projected.resource_spans
[scope] = resource.scope_spans
[actual] = scope.spans
true = Map.drop(actual, [:attributes]) == Map.drop(span, [:attributes])
true = resource.resource == hd(request.resource_spans).resource
true = scope.scope == hd(hd(request.resource_spans).scope_spans).scope

for native <- attrs do
  true = %{native | key: "opik.metadata." <> native.key} in actual.attributes
end

true = attribute.("opik.metadata.resource.test.false", :bool_value, false) in actual.attributes

true = attribute.("gen_ai.usage.input_tokens", :int_value, 3) in actual.attributes

tool = %{
  span
  | attributes: [
      attribute.("exagent.operation", :string_value, "tool"),
      attribute.("gen_ai.tool.name", :string_value, "synthetic_tool")
    ]
}

tool_request =
  put_in(request, [:resource_spans], [
    %{hd(request.resource_spans) | scope_spans: [%{scope | spans: [tool]}]}
  ])

[%{scope_spans: [%{spans: [actual_tool]}]}] = Profile.project(tool_request).resource_spans

false =
  Enum.any?(actual_tool.attributes, &String.starts_with?(&1.key, "gen_ai.tool.call.arguments"))

true = Map.drop(actual_tool, [:attributes]) == Map.drop(tool, [:attributes])

oversized =
  put_in(request, [:resource_spans], [
    %{
      hd(request.resource_spans)
      | scope_spans: [
          %{
            scope
            | spans: [
                %{span | attributes: Enum.map(1..65, &attribute.("test.#{&1}", :int_value, &1))}
              ]
          }
        ]
    }
  ])

try do
  Profile.project(oversized)
  raise "oversized projection accepted"
rescue
  MatchError -> :ok
end

IO.puts(
  "OPIK_PROFILE_CONTROL passed: native identity, status, time, scalars, privacy and finite expansion"
)
