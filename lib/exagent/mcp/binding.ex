defmodule ExAgent.MCP.Binding do
  @moduledoc false
  alias ExAgent.Continuation.Record

  # Host references declare stable identities; they neither authenticate the
  # peer nor prove that two credentials belong to the same principal.
  def from_options(opts) do
    case Keyword.get(opts, :continuation_binding) do
      nil ->
        {:ok, :unbound}

      %{endpoint: endpoint, principal: principal} = identity when map_size(identity) == 2 ->
        with true <- Record.reference?(endpoint) and Record.reference?(principal),
             {:ok, transport, protocol, target} <- target(opts) do
          descriptor = %{
            "binding_version" => 1,
            "adapter" => "mcp",
            "endpoint" => endpoint,
            "principal" => principal,
            "transport" => transport,
            "protocol_version" => protocol
          }

          descriptor = if target, do: Map.put(descriptor, "target_hash", target), else: descriptor
          if valid?(descriptor), do: {:ok, descriptor}, else: invalid()
        else
          _ -> invalid()
        end

      _ ->
        invalid()
    end
  rescue
    _ -> invalid()
  end

  defp target(opts) do
    case opts[:transport] do
      :streamable_http ->
        with true <- Keyword.get(opts, :protocol_version, "2025-06-18") === "2025-06-18",
             {:ok, url} <- public_url(opts[:url]) do
          {:ok, "streamable_http", "2025-06-18", hash(url)}
        else
          _ -> invalid()
        end

      _ ->
        protocol = Keyword.get(opts, :protocol_version, "2024-11-05")
        if Record.text?(protocol), do: {:ok, "stdio", protocol, nil}, else: invalid()
    end
  end

  # URI syntax aliases only. No IO, DNS equivalence, path/query normalization,
  # credential hashing or peer-supplied identity participates in authority.
  defp public_url(url) when is_binary(url) and byte_size(url) <= 8_192 do
    case URI.parse(url) do
      %URI{scheme: scheme, host: host, userinfo: nil, query: nil, fragment: nil} = uri
      when scheme in ["http", "https"] and is_binary(host) and host != "" ->
        {:ok, URI.to_string(%{uri | host: String.downcase(host), path: uri.path || "/"})}

      _ ->
        invalid()
    end
  end

  defp public_url(_), do: invalid()

  def valid?(data) do
    is_map(data) and
      Record.exact?(
        data,
        ~w(binding_version adapter endpoint principal transport protocol_version) ++
          if(data["transport"] == "streamable_http", do: ["target_hash"], else: [])
      ) and
      data["binding_version"] === 1 and data["adapter"] === "mcp" and
      Record.reference?(data["endpoint"]) and Record.reference?(data["principal"]) and
      case data["transport"] do
        "stdio" ->
          Record.text?(data["protocol_version"])

        "streamable_http" ->
          data["protocol_version"] === "2025-06-18" and hash?(data["target_hash"])

        _ ->
          false
      end
  rescue
    _ -> false
  end

  defp hash(value), do: :crypto.hash(:sha256, value) |> Base.encode16(case: :lower)
  defp hash?(value), do: is_binary(value) and Regex.match?(~r/\A[0-9a-f]{64}\z/, value)
  defp invalid, do: {:error, :invalid_mcp_continuation_binding}
end
