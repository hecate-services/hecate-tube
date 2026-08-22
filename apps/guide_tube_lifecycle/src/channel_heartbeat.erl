%% @doc Timer-driven re-publish of every channel's current snapshot,
%% every 60s regardless of new writes (Demon #45 -- fire-once publishing
%% over an unreliable transport is a previously-burned bug in this
%% workspace). A plain gen_server, not an evoq behaviour: this reacts to
%% a timer, not a domain event, so evoq_event_handler doesn't fit (its
%% callback module has no hook for arbitrary messages) and Demon #39 (no
%% raw gen_servers for event reaction) doesn't apply -- there is no event
%% here to react to.
-module(channel_heartbeat).

-behaviour(gen_server).

-export([start_link/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

-define(HEARTBEAT_MS, 60_000).

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

init([]) ->
    schedule(),
    {ok, undefined}.

handle_call(_Msg, _From, State) -> {reply, {error, unknown_call}, State}.
handle_cast(_Msg, State) -> {noreply, State}.

handle_info(heartbeat, State) ->
    lists:foreach(fun(ChannelId) -> channel_announcement:announce(ChannelId, <<"heartbeat">>) end,
                 project_tube_store:list_channel_ids()),
    schedule(),
    {noreply, State};
handle_info(_Msg, State) -> {noreply, State}.

terminate(_Reason, _State) -> ok.

schedule() -> erlang:send_after(?HEARTBEAT_MS, self(), heartbeat).
