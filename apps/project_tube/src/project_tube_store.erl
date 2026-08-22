%% @doc The read-model store facade every QRY desk reads through directly,
%% mirroring hecate-mpong-bot's project_mpong_games_store.erl. Owns one ETS
%% table per read model; projections write here, QRY desks read here --
%% neither ever touches ETS directly.
-module(project_tube_store).

-behaviour(gen_server).

-export([start_link/0]).
-export([get_channel/1, put_channel/2, list_channel_ids/0, list_channels/0]).
-export([get_clip/1, put_clip/2, list_clips_by_channel/1,
         increment_clip_view_count/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

-define(CHANNELS, tube_channels).
-define(CLIPS, tube_video_clips).

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

-spec get_channel(binary()) -> {ok, map()} | {error, not_found}.
get_channel(ChannelId) ->
    case ets:lookup(?CHANNELS, ChannelId) of
        [{ChannelId, Row}] -> {ok, Row};
        []                 -> {error, not_found}
    end.

-spec put_channel(binary(), map()) -> ok.
put_channel(ChannelId, Row) ->
    gen_server:call(?MODULE, {put_channel, ChannelId, Row}).

-spec list_channel_ids() -> [binary()].
list_channel_ids() ->
    ets:foldl(fun({ChannelId, _Row}, Acc) -> [ChannelId | Acc] end, [], ?CHANNELS).

-spec list_channels() -> [map()].
list_channels() ->
    ets:foldl(fun({_ChannelId, Row}, Acc) -> [Row | Acc] end, [], ?CHANNELS).

-spec get_clip(binary()) -> {ok, map()} | {error, not_found}.
get_clip(ClipId) ->
    case ets:lookup(?CLIPS, ClipId) of
        [{ClipId, Row}] -> {ok, Row};
        []              -> {error, not_found}
    end.

%% @doc Preserves `view_count' across writes -- every lifecycle event
%% (upload/publish/retract/archive) rebuilds the row from the domain
%% event's own data, which never carries view_count (that's tracked here
%% only, incremented separately), so a naive overwrite would reset it.
-spec put_clip(binary(), map()) -> ok.
put_clip(ClipId, Row) ->
    gen_server:call(?MODULE, {put_clip, ClipId, Row}).

%% @doc Every clip belonging to `ChannelId', published or not -- callers
%% that only want published ones (the mesh-facing surface) filter on
%% `status' themselves; this facade stays a dumb store, no business rules.
-spec list_clips_by_channel(binary()) -> [map()].
list_clips_by_channel(ChannelId) ->
    ets:foldl(fun({_ClipId, Row}, Acc) ->
                 accumulate_if_channel(ChannelId, Row, Acc)
              end, [], ?CLIPS).

accumulate_if_channel(ChannelId, #{channel_id := ChannelId} = Row, Acc) ->
    [Row | Acc];
accumulate_if_channel(_ChannelId, _Row, Acc) ->
    Acc.

%% @doc +1 on a clip's view_count. Safe as a plain read-modify-write:
%% every write to this table already funnels through this gen_server's
%% single mailbox, so there is no concurrent-writer race to guard
%% against with e.g. ets:update_counter/3 (which wouldn't apply here
%% anyway -- view_count lives inside a map value, not a fixed tuple
%% position).
-spec increment_clip_view_count(binary()) -> ok.
increment_clip_view_count(ClipId) ->
    gen_server:call(?MODULE, {increment_clip_view_count, ClipId}).

init([]) ->
    ets:new(?CHANNELS, [set, public, named_table, {read_concurrency, true}]),
    ets:new(?CLIPS, [set, public, named_table, {read_concurrency, true}]),
    {ok, #{}}.

handle_call({put_channel, ChannelId, Row}, _From, State) ->
    true = ets:insert(?CHANNELS, {ChannelId, Row}),
    {reply, ok, State};
handle_call({put_clip, ClipId, Row}, _From, State) ->
    true = ets:insert(?CLIPS, {ClipId, Row#{view_count => existing_view_count(ClipId)}}),
    {reply, ok, State};
handle_call({increment_clip_view_count, ClipId}, _From, State) ->
    ok = do_increment_clip_view_count(ClipId),
    {reply, ok, State};
handle_call(_Msg, _From, State) ->
    {reply, {error, unknown_call}, State}.

handle_cast(_Msg, State) -> {noreply, State}.
handle_info(_Msg, State) -> {noreply, State}.
terminate(_Reason, _State) -> ok.

existing_view_count(ClipId) ->
    existing_view_count_from(ets:lookup(?CLIPS, ClipId)).

existing_view_count_from([{_ClipId, #{view_count := V}}]) -> V;
existing_view_count_from(_NoRow) -> 0.

do_increment_clip_view_count(ClipId) ->
    increment_from(ets:lookup(?CLIPS, ClipId), ClipId).

increment_from([{ClipId, Row}], ClipId) ->
    Count = maps:get(view_count, Row, 0),
    true = ets:insert(?CLIPS, {ClipId, Row#{view_count => Count + 1}}),
    ok;
increment_from([], _ClipId) ->
    ok.
