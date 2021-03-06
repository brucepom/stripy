defmodule Stripy do
  @moduledoc """
  Stripy is a micro wrapper intended to be
  used for sending requests to Stripe's REST API. It is
  made for developers who prefer to work directly with the
  official API and provide their own abstractions on top
  if such are needed.

  Stripy takes care of setting headers, encoding the data,
  configuration settings, etc (the usual boring boilerplate);
  it also provides a `parse/1` helper function for decoding.

  Some basic examples:

      iex> Stripy.req(:get, "subscriptions")
      {:ok, %HTTPoison.Response{...}}

      iex> Stripy.req(:post, "customers", %{"email" => "a@b.c", "metadata[user_id]" => 1})
      {:ok, %HTTPoison.Response{...}}

  You are expected to build your business logic on top
  of Stripy and abstract things such as Subscriptions
  and Customers; if that's not your cup of tea,
  check out "stripity_stripe" or "stripe_elixir" on Hex.
  """

  @content_type_header %{"Content-Type" => "application/x-www-form-urlencoded"}

  @doc "Constructs url with query params from given data."
  def url(api_url, resource, data) do
    api_url <> resource <> "?" <> URI.encode_query(data)
  end

  @doc """
  Makes request to the Stripe API.

  Will return an HTTPoison standard response; see `parse/1`
  for decoding the response body.

  You can specify custom headers to be included in the request
  to Stripe, such as `Idempotency-Key`, `Stripe-Account` or any
  other header. Just pass a map as the fourth argument.
  See example below.

  ## Examples
      iex> Stripy.req(:get, "subscriptions")
      {:ok, %HTTPoison.Response{...}}

      iex> Stripy.req(:post, "customers", %{"email" => "a@b.c", "metadata[user_id]" => 1})
      {:ok, %HTTPoison.Response{...}}

      iex> Stripy.req(:post, "customers", %{"email" => "a@b.c"}, %{"Idempotency-Key" => "ABC"})
      {:ok, %HTTPoison.Response{...}}
  """
  def req(action, resource, data \\ %{}, headers \\ %{}, opts \\ []) when action in [:get, :post, :delete] do
    if Application.get_env(:stripy, :testing, false) do
      mock_server = Application.get_env(:stripy, :mock_server, Stripy.MockServer)
      mock_server.request(action, resource, data)
    else
      IO.inspect opts: opts
      IO.inspect secret_key: Keyword.get(opts, :secret_key)
      secret_key = Keyword.get(opts, :secret_key) || Application.fetch_env!(:stripy, :secret_key)

      headers =
        @content_type_header
        |> Map.merge(%{
          "Authorization" => "Bearer #{secret_key}",
          "Stripe-Version" => Application.get_env(:stripy, :version, "2017-06-05")
        })
        |> Map.merge(headers)
        |> Map.to_list()

      api_url = Application.get_env(:stripy, :endpoint, "https://api.stripe.com/v1/")
      options = Application.get_env(:stripy, :httpoison, [])

      url = url(api_url, resource, data)
      HTTPoison.request(action, url, "", headers, options)
    end
  end

  @doc "Parses an HTTPoison response from a Stripe API call."
  def parse({:ok, %{status_code: 200, body: body}}) do
    {:ok, Poison.decode!(body)}
  end

  def parse({:ok, %{body: body}}) do
    error = Poison.decode!(body) |> Map.fetch!("error")
    {:error, error}
  end

  def parse({:error, error}), do: {:error, error}
end
