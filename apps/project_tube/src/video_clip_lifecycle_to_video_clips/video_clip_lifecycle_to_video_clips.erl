%% @doc Projection: video_clip lifecycle events -> tube_video_clips table.
%%
%% The evoq_read_model handle is a checkpoint passthrough only -- actual
%% data lives in project_tube_store's ETS table, matching
%% channel_lifecycle_to_channels's own shape.
%%
%% `status' here is a plain display-friendly binary
%% (<<"uploaded">>/<<"published">>/<<"archived">>), not the aggregate's
%% bit-flag integer (guide_tube_lifecycle/include/tube_video_clip_status.hrl)
%% -- a read model denormalizes for its own consumers rather than
%% mirroring write-side internals, and this avoids a cross-app header
%% dependency PRJ has no other reason to take on CMD for.
-module(video_clip_lifecycle_to_video_clips).

-behaviour(evoq_projection).

-export([interested_in/0, init/1, project/4]).

interested_in() ->
    [<<"video_clip_uploaded_v1">>, <<"video_clip_published_v1">>,
     <<"video_clip_retracted_v1">>, <<"video_clip_archived_v1">>,
     <<"video_clip_viewed_v1">>].

init(_Config) ->
    {ok, RM} = evoq_read_model:new(evoq_read_model_ets,
                                   #{name => tube_video_clips_projection}),
    {ok, #{}, RM}.

project(#{event_type := <<"video_clip_uploaded_v1">>, data := Data}, _Metadata, State, RM) ->
    ClipId = field(clip_id, Data),
    Row = #{
        clip_id        => ClipId,
        channel_id     => field(channel_id, Data),
        name           => field(name, Data),
        description    => field(description, Data),
        tags           => field(tags, Data),
        thumbnail_mcid => field(thumbnail_mcid, Data),
        %% local_ref is edge-node-only -- fine to hold in THIS read model
        %% (in-memory, never serialized to the mesh); the privacy rule is
        %% that it never rides a mesh fact or RPC reply. The streaming
        %% provider desk reads it from here to find the file to stream.
        local_ref      => field(local_ref, Data),
        status         => <<"uploaded">>
    },
    ok = project_tube_store:put_clip(ClipId, Row),
    {ok, State, RM};
project(#{event_type := <<"video_clip_published_v1">>, data := Data}, _Metadata, State, RM) ->
    ok = set_status(field(clip_id, Data), <<"published">>),
    {ok, State, RM};
%% retract returns the clip to private -- the same UPLOADED-equivalent
%% status publish started from, symmetric with the aggregate's own
%% bit-clear (spec's "minimal ceremony": no separate state needed).
project(#{event_type := <<"video_clip_retracted_v1">>, data := Data}, _Metadata, State, RM) ->
    ok = set_status(field(clip_id, Data), <<"uploaded">>),
    {ok, State, RM};
project(#{event_type := <<"video_clip_archived_v1">>, data := Data}, _Metadata, State, RM) ->
    ok = set_status(field(clip_id, Data), <<"archived">>),
    {ok, State, RM};
project(#{event_type := <<"video_clip_viewed_v1">>, data := Data}, _Metadata, State, RM) ->
    ok = project_tube_store:increment_clip_view_count(field(clip_id, Data)),
    {ok, State, RM}.

set_status(ClipId, Status) ->
    apply_status(project_tube_store:get_clip(ClipId), ClipId, Status).

apply_status({ok, Row}, ClipId, Status) ->
    project_tube_store:put_clip(ClipId, Row#{status => Status});
apply_status({error, not_found}, _ClipId, _Status) ->
    ok.

field(Key, Map) when is_atom(Key) ->
    BinKey = atom_to_binary(Key, utf8),
    maps:get(Key, Map, maps:get(BinKey, Map, undefined)).
