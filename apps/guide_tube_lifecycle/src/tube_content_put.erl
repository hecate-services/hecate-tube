%% @doc Synchronous wrapper around macula_feeder for the owner UI's logo/
%% thumbnail uploads -- the HTTP handler needs the resulting MCID before it
%% can build the initiate_channel/reconfigure_channel/upload_video_clip
%% params, so this blocks (with a timeout) for the async feeder's outcome
%% rather than returning a pid the caller has nothing to do with.
%%
%% Degrades to `{ok, undefined}' (no logo/thumbnail, not an error) when the
%% mesh is unreachable -- an owner configuring a channel offline shouldn't
%% be blocked by a missing mesh connection for an optional image.
%%
%% ALSO persists a durable local copy via `tube_content_store', keyed by
%% the minted MCID. `macula:put_content/2' (which macula_feeder drives) is
%% a one-time peer-to-peer transfer, not storage -- nothing else retains
%% the bytes past that single push, so a later, unrelated caller's
%% `tube.lookup_content' request is served from this local copy instead.
-module(tube_content_put).

-behaviour(macula_feeder).

-export([put/1]).
-export([init/1, handle_fed/2]).
%% Exported for tube_content_put_tests.erl -- pure logic, same testing
%% convention tube_mesh_providers_tests.erl already uses for reuse_opts/1.
-export([persist_then_return/2]).

-define(TIMEOUT_MS, 30_000).

-spec put(binary()) -> {ok, binary() | undefined} | {error, term()}.
put(Bytes) when is_binary(Bytes) ->
    persist_then_return(put_via(hecate_om:mesh_handles(), Bytes), Bytes).

persist_then_return({ok, Mcid}, Bytes) when is_binary(Mcid) ->
    ok = tube_content_store:persist(binary:encode_hex(Mcid, lowercase), Bytes),
    {ok, Mcid};
persist_then_return(Result, _Bytes) ->
    Result.

put_via({ok, Pool, Realm}, Bytes) ->
    {ok, Pid} = macula_feeder:start_link(?MODULE, Pool, Realm, Bytes, self()),
    await(Pid);
put_via({error, _}, _Bytes) ->
    {ok, undefined}.

await(Pid) ->
    receive
        {tube_content_put_result, Pid, {ok, Mcid}} -> {ok, Mcid};
        {tube_content_put_result, Pid, {error, Reason}} -> {error, Reason}
    after ?TIMEOUT_MS ->
        catch macula_feeder:cancel(Pid),
        {error, timeout}
    end.

init(Parent) -> {ok, Parent}.

handle_fed(Result, Parent) ->
    Parent ! {tube_content_put_result, self(), Result},
    {stop, normal, Parent}.
