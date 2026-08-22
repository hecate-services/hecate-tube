%% @doc Synchronous wrapper around macula_download for the owner UI's
%% content rendering (a channel logo, so far) -- the HTTP handler needs
%% the bytes before it can reply, so this blocks (with a timeout) for
%% the async download's outcome, mirroring tube_content_put's own shape
%% for the opposite direction.
%%
%% Pooled `start_link/4,5', not `start_link_direct/4,5' -- corrected
%% after a live 404 on beam02 traced to macula_download's own
%% moduledoc: "Only chunked content is discoverable this way [via
%% start_link_direct's DHT content_announcement resolve] -- see
%% macula:find_content_providers/2". A channel logo is a few hundred
%% bytes to a couple KB, nowhere near macula's chunking threshold, so
%% it never gets a content_announcement record at all -- direct-dial
%% resolution can't ever succeed for it, confirmed live: `{error,
%% {unresolved, content_not_announced}}' even immediately after the
%% station's own upload. `tube_content_put' puts it via the pooled
%% `macula_feeder:start_link/4,5' (not `_direct'); the get side has to
%% match, fetching "via `Pool`'s own connected link" the same way
%% instead of trying to resolve a DHT record that will never exist.
-module(tube_content_get).

-behaviour(macula_download).

-export([get/1]).
-export([init/1, handle_downloaded/2]).

-define(TIMEOUT_MS, 15_000).

-spec get(binary()) -> {ok, binary()} | {error, term()}.
get(Mcid) when is_binary(Mcid) ->
    get_via(hecate_om:mesh_handles(), Mcid).

get_via({ok, Pool, Realm}, Mcid) ->
    {ok, Pid} = macula_download:start_link(?MODULE, Pool, Realm, Mcid, self()),
    await(Pid);
get_via({error, _} = Error, _Mcid) ->
    Error.

await(Pid) ->
    receive
        {tube_content_get_result, Pid, Result} -> Result
    after ?TIMEOUT_MS ->
        catch macula_download:cancel(Pid),
        {error, timeout}
    end.

init(Parent) -> {ok, Parent}.

handle_downloaded(Result, Parent) ->
    Parent ! {tube_content_get_result, self(), Result},
    {stop, normal, Parent}.
