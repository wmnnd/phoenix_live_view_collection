defmodule LiveViewCollection.Collection do
  use GenServer
  require Logger

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec all() :: [map()]
  def all do
    GenServer.call(__MODULE__, :all)
  end

  @spec count() :: non_neg_integer()
  def count do
    GenServer.call(__MODULE__, :count)
  end

  @spec count(String.t()) :: non_neg_integer()
  def count(search) do
    GenServer.call(__MODULE__, {:count, search})
  end

  @spec fetch(Keyword.t()) :: [map()]
  def fetch(opts \\ []) do
    search = Keyword.get(opts, :search)
    page = Keyword.get(opts, :page, 1)
    GenServer.call(__MODULE__, {:fetch, search, page})
  end

  def default_page_size, do: 4

  ## Callbacks

  @impl GenServer
  def init(state) do
    send(self(), :load_collection)
    {:ok, state}
  end

  @impl GenServer
  def handle_info(:load_collection, _state) do
    collection =
      with {:ok, collection} <- YamlElixir.read_from_file(Path.join(File.cwd!(), "collection.yml")),
           {:ok, collection} <- request_embeded_tweets(collection) do
        collection
      else
        {:error, error} ->
          Logger.error(fn -> "Error loading collection: #{inspect(error)}" end)
          []
      end

    {:noreply, collection}
  end

  defp request_embeded_tweets([]), do: {:ok, []}

  defp request_embeded_tweets(collection) do
    fetch_tweet = fn tweet_url ->
      with {:ok, %{body: body}} <-
             Mojito.request(
               method: :get,
               url: "https://publish.twitter.com/oembed?url=#{tweet_url}&omit_script=true&hide_thread=true"
             ),
           {:ok, tweet} <- Jason.decode(body) do
        tweet
      else
        {:error, error} ->
          Logger.error(fn -> "Error fetching embeded tweet: #{inspect(error)}" end)
          nil
      end
    end

    {:ok,
     collection
     |> Enum.map(&fetch_tweet.(&1["tweet_url"]))
     |> Enum.reject(&is_nil/1)}
  end

  @impl GenServer
  def handle_call(:all, _from, state) do
    {:reply, state, state}
  end

  def handle_call(:count, _from, state) do
    {:reply, length(state), state}
  end

  def handle_call({:count, search}, _from, state) do
    count = state |> do_filter(search) |> length()
    {:reply, count, state}
  end

  def handle_call({:fetch, search, page}, _from, state) do
    result =
      state
      |> do_filter(search)
      |> do_paginate(page)

    {:reply, result, state}
  end

  defp do_filter(collection, search) when is_nil(search) or search == "", do: collection

  defp do_filter(collection, search) do
    {:ok, regex} = Regex.compile(search, "i")

    Enum.filter(collection, fn %{"html" => search} ->
      String.match?(search, regex)
    end)
  end

  defp do_paginate(collection, page) when is_nil(page) or page <= 0 do
    do_paginate(collection, 1)
  end

  defp do_paginate(collection, page) do
    Enum.slice(collection, (page - 1) * default_page_size(), default_page_size())
  end
end