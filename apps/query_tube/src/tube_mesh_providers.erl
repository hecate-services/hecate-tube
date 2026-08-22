%% @doc Advertises hecate-tube's mesh-facing RPC and Streaming providers
%% (tube.lookup_channel, tube.lookup_video_clip, tube.watch_video_clip)
%% via direct-dial, retrying until the mesh pool and this service's
%% keypair are both available -- hecate_om_identity connects off its own
%% init path, asynchronously, so a single inline attempt at boot can
%% race it and lose, the same race hecate_om_identity's own retry exists
%% to avoid.
%%
%% Advertises ONCE it succeeds, not on a repeating timer, unlike
%% hecate_om_capabilities's own re-publish pattern: that one re-asserts
%% idempotent DHT records (macula:put_record); macula_response:advertise_direct/6,7
%% and macula_streamer:advertise_direct/6,7 each start a NEW, unsupervised
%% factory supervisor on every call (see their own source), so a
%% repeating re-advertise would leak one orphaned supervisor per
%% interval. A stale DHT record after a pool reconnect (a new station
%% link) is a known, un-addressed gap left for a later session -- see
%% plans/EVENT_STORM_HECATE_TUBE.md sec 12, the running hecate-om
%% findings log this belongs in.
-module(tube_mesh_providers).

-behaviour(gen_server).

-export([start_link/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

-define(RETRY_MS, 5000).

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

init([]) ->
    self() ! advertise,
    {ok, #{advertised => false}}.

handle_call(_Msg, _From, State) -> {reply, {error, unknown_call}, State}.
handle_cast(_Msg, State) -> {noreply, State}.

handle_info(advertise, #{advertised := true} = State) ->
    {noreply, State};
handle_info(advertise, State) ->
    {noreply, try_advertise(hecate_om:mesh_handles(), hecate_om:keypair(), State)};
handle_info(_Msg, State) -> {noreply, State}.

terminate(_Reason, _State) -> ok.

try_advertise({ok, Pool, Realm}, {ok, KeyPair}, State) ->
    {ok, ChannelSup} = macula_response:advertise_direct(
        Pool, Realm, <<"tube.lookup_channel">>, advertise_channel_lookup, [], KeyPair),
    {ok, ClipSup} = macula_response:advertise_direct(
        Pool, Realm, <<"tube.lookup_video_clip">>, advertise_video_clip_lookup, [], KeyPair),
    {ok, StreamSup} = macula_streamer:advertise_direct(
        Pool, Realm, <<"tube.watch_video_clip">>, stream_video_clip_by_id, [], KeyPair),
    State#{advertised => true, channel_sup => ChannelSup,
          clip_sup => ClipSup, stream_sup => StreamSup};
try_advertise(_MeshHandles, _KeyPair, State) ->
    erlang:send_after(?RETRY_MS, self(), advertise),
    State.
