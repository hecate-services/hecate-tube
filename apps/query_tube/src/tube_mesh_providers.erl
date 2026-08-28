%% @doc Advertises hecate-tube's mesh-facing RPC and Streaming providers
%% (tube.lookup_channel, tube.lookup_video_clip, tube.watch_video_clip,
%% tube.lookup_content) via direct-dial, retrying until the mesh pool and this service's
%% keypair are both available -- hecate_om_identity connects off its own
%% init path, asynchronously, so a single inline attempt at boot can
%% race it and lose, the same race hecate_om_identity's own retry exists
%% to avoid.
%%
%% Re-advertises on a repeating timer once the first attempt succeeds,
%% using `reuse_sup' (macula >= 10.1.0) to resend the wire ADVERTISE
%% frame and republish the DHT record without leaking a new factory
%% supervisor per tick. This used to advertise once and never again --
%% a real, confirmed-live gap: a station's wire-level registration for
%% a procedure is tied to whichever connection sent it, and does not
%% survive that connection being replaced (reconnect, station-side
%% eviction, a newer handshake from the same identity superseding the
%% old one). `advertised => true' here is local bookkeeping only --
%% "we successfully advertised at some point" -- never re-checked
%% against whether that registration is still live on the station side,
%% which is exactly why a one-shot advertise went stale silently.
-module(tube_mesh_providers).

-behaviour(gen_server).

-export([start_link/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).
%% Exported for tube_mesh_providers_tests.erl -- pure logic, same
%% testing convention hecate_om_identity_tests.erl already uses.
-export([reuse_opts/1]).

-define(RETRY_MS, 5000).
-define(READVERTISE_MS, 60_000).

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

init([]) ->
    self() ! advertise,
    {ok, #{advertised => false}}.

handle_call(_Msg, _From, State) -> {reply, {error, unknown_call}, State}.
handle_cast(_Msg, State) -> {noreply, State}.

handle_info(advertise, State) ->
    {noreply, try_advertise(hecate_om:mesh_handles(), hecate_om:keypair(), State)};
handle_info(_Msg, State) -> {noreply, State}.

terminate(_Reason, _State) -> ok.

try_advertise({ok, Pool, Realm}, {ok, KeyPair}, State) ->
    Opts = reuse_opts(State),
    {ok, ChannelSup} = macula_response:advertise_direct(
        Pool, Realm, <<"tube.lookup_channel">>, advertise_channel_lookup, [],
        KeyPair, Opts(channel_sup)),
    {ok, ClipSup} = macula_response:advertise_direct(
        Pool, Realm, <<"tube.lookup_video_clip">>, advertise_video_clip_lookup, [],
        KeyPair, Opts(clip_sup)),
    {ok, StreamSup} = macula_streamer:advertise_direct(
        Pool, Realm, <<"tube.watch_video_clip">>, stream_video_clip_by_id, [],
        KeyPair, Opts(stream_sup)),
    {ok, ContentSup} = macula_response:advertise_direct(
        Pool, Realm, <<"tube.lookup_content">>, advertise_content_lookup, [],
        KeyPair, Opts(content_sup)),
    erlang:send_after(?READVERTISE_MS, self(), advertise),
    State#{advertised => true, channel_sup => ChannelSup,
          clip_sup => ClipSup, stream_sup => StreamSup,
          content_sup => ContentSup};
try_advertise(_MeshHandles, _KeyPair, State) ->
    erlang:send_after(?RETRY_MS, self(), advertise),
    State.

%% Returns a `Key -> Opts' fun: `#{reuse_sup => Sup}' once this
%% procedure has a supervisor from a prior advertise, `#{}' (start a
%% fresh one) the first time.
reuse_opts(State) ->
    fun(Key) -> reuse_opt(maps:find(Key, State)) end.

reuse_opt({ok, Sup}) -> #{reuse_sup => Sup};
reuse_opt(error)     -> #{}.
