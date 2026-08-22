%% @doc Synchronous wrapper around macula_download for the owner UI's
%% content rendering (a channel logo, so far) -- the HTTP handler needs
%% the bytes before it can reply, so this blocks (with a timeout) for
%% the async download's outcome, mirroring tube_content_put's own shape
%% for the opposite direction.
%%
%% Always start_link_direct, never the pooled start_link -- matches
%% every other Content consumer in this codebase (plans/
%% EVENT_STORM_HECATE_TUBE_PART1.md sec 5.4): resolves the MCID's
%% provider via its content_announcement rather than assuming this
%% station already holds a copy, even though for an owner's own
%% recently-uploaded logo that's often true in practice.
-module(tube_content_get).

-behaviour(macula_download).

-export([get/1]).
-export([init/1, handle_downloaded/2]).

-define(TIMEOUT_MS, 15_000).

-spec get(binary()) -> {ok, binary()} | {error, term()}.
get(Mcid) when is_binary(Mcid) ->
    get_via(hecate_om:mesh_handles(), Mcid).

get_via({ok, Pool, Realm}, Mcid) ->
    {ok, Pid} = macula_download:start_link_direct(?MODULE, Pool, Realm, Mcid, self()),
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
