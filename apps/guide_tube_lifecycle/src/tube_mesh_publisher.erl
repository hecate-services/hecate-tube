%% @doc Trivial fire-and-forget macula_publisher callback shared by every
%% mesh-fact emitter in this app -- none of them need to react to the
%% publish outcome, they just want the supervised pid/mesh-fact machinery
%% macula_publisher already provides around a bare macula:publish/4.
-module(tube_mesh_publisher).

-behaviour(macula_publisher).

-export([init/1, handle_published/2]).

init(_Args) -> {ok, undefined}.

handle_published(_Result, State) -> {stop, normal, State}.
