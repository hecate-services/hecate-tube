%% @doc Projection: channel_initiated_v1 / channel_reconfigured_v1 ->
%% tube_channels table.
%%
%% The evoq_read_model handle is a checkpoint passthrough only -- actual
%% data lives in project_tube_store's ETS table, not in the read model
%% itself, matching hecate-mpong-bot's game_lifecycle_to_mpong_games.erl.
-module(channel_lifecycle_to_channels).

-behaviour(evoq_projection).

-export([interested_in/0, init/1, project/4]).

interested_in() -> [<<"channel_initiated_v1">>, <<"channel_reconfigured_v1">>].

init(_Config) ->
    {ok, RM} = evoq_read_model:new(evoq_read_model_ets,
                                   #{name => tube_channels_projection}),
    {ok, #{}, RM}.

%% `Event' here is what evoq_store_subscription:evoq_event_to_routable/1
%% builds: #{event_type, event_id, stream_id, version, data, tags,
%% timestamp, epoch_us} -- the actual event fields are nested under
%% `data', not top-level. `field/2' is additionally atom-or-binary
%% tolerant since a round trip through the store is not guaranteed to
%% preserve atom keys.
project(#{event_type := <<"channel_initiated_v1">>, data := Data}, _Metadata, State, RM) ->
    ChannelId = field(channel_id, Data),
    Row = #{
        channel_id  => ChannelId,
        name        => field(name, Data),
        description => field(description, Data),
        owner       => field(owner, Data),
        tags        => field(tags, Data),
        logo_mcid   => field(logo_mcid, Data)
    },
    ok = project_tube_store:put_channel(ChannelId, Row),
    {ok, State, RM};
%% owner never changes and reconfigure doesn't carry it -- read back off
%% the existing row and re-written unchanged rather than lost.
project(#{event_type := <<"channel_reconfigured_v1">>, data := Data}, _Metadata, State, RM) ->
    ChannelId = field(channel_id, Data),
    Row = #{
        channel_id  => ChannelId,
        name        => field(name, Data),
        description => field(description, Data),
        owner       => existing_owner(ChannelId),
        tags        => field(tags, Data),
        logo_mcid   => field(logo_mcid, Data)
    },
    ok = project_tube_store:put_channel(ChannelId, Row),
    {ok, State, RM}.

existing_owner(ChannelId) ->
    owner_from(project_tube_store:get_channel(ChannelId)).

owner_from({ok, Row}) -> maps:get(owner, Row, undefined);
owner_from({error, not_found}) -> undefined.

field(Key, Map) when is_atom(Key) ->
    BinKey = atom_to_binary(Key, utf8),
    maps:get(Key, Map, maps:get(BinKey, Map, undefined)).
