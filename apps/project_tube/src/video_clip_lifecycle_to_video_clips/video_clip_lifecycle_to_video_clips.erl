%% @doc Projection: video_clip lifecycle events -> tube_video_clips table.
%%
%% The evoq_read_model handle is a checkpoint passthrough only -- actual
%% data lives in project_tube_store's ETS table, matching
%% channel_lifecycle_to_channels's own shape.
%%
%% `status' here is a plain display-friendly binary
%% (<<"uploaded">>/<<"published">>/<<"archived">>/<<"rejected">>), not
%% the aggregate's
%% bit-flag integer (guide_tube_lifecycle/include/tube_video_clip_status.hrl)
%% -- a read model denormalizes for its own consumers rather than
%% mirroring write-side internals, and this avoids a cross-app header
%% dependency PRJ has no other reason to take on CMD for.
-module(video_clip_lifecycle_to_video_clips).

-behaviour(evoq_projection).

-export([interested_in/0, init/1, project/4]).

interested_in() ->
    [<<"video_clip_uploaded_v1">>, <<"video_clip_scanned_v1">>,
     <<"video_clip_accepted_v1">>, <<"video_clip_rejected_v1">>,
     <<"video_clip_published_v1">>, <<"video_clip_retracted_v1">>,
     <<"video_clip_archived_v1">>, <<"video_clip_viewed_v1">>].

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
%% Measurements only -- doesn't touch `status'. The accepted/rejected
%% verdict that follows (same dispatch, same request) is what changes
%% status; see video_clip_scanned_v1.erl for why the two are separate
%% events.
project(#{event_type := <<"video_clip_scanned_v1">>, data := Data}, _Metadata, State, RM) ->
    ok = merge_clip(field(clip_id, Data), #{
        duration_ms      => field(duration_ms, Data),
        width            => field(width, Data),
        height           => field(height, Data),
        codec            => field(codec, Data),
        container_format => field(container_format, Data),
        file_size_bytes  => field(file_size_bytes, Data),
        has_audio        => field(has_audio, Data),
        thumbnail_mcid   => field(thumbnail_mcid, Data)
    }),
    {ok, State, RM};
%% No-op: an accepted clip is already `<<"uploaded">>' (private,
%% publishable) from the uploaded event moments earlier in the same
%% dispatch -- accepted doesn't introduce a new displayed state,
%% rejected does (below).
project(#{event_type := <<"video_clip_accepted_v1">>}, _Metadata, State, RM) ->
    {ok, State, RM};
project(#{event_type := <<"video_clip_rejected_v1">>, data := Data}, _Metadata, State, RM) ->
    ok = merge_clip(field(clip_id, Data), #{
        status          => <<"rejected">>,
        rejected_reason => field(reason, Data)
    }),
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
    merge_clip(ClipId, #{status => Status}).

%% @doc Read-modify-write: merges `Fields' into the clip's existing
%% row. A no-op if the row doesn't exist yet -- shouldn't happen in
%% practice (uploaded always projects first, same dispatch), but a
%% projection tolerating an out-of-order replay is cheaper than
%% guaranteeing one never happens.
merge_clip(ClipId, Fields) ->
    apply_merge(project_tube_store:get_clip(ClipId), ClipId, Fields).

apply_merge({ok, Row}, ClipId, Fields) ->
    project_tube_store:put_clip(ClipId, maps:merge(Row, Fields));
apply_merge({error, not_found}, _ClipId, _Fields) ->
    ok.

field(Key, Map) when is_atom(Key) ->
    BinKey = atom_to_binary(Key, utf8),
    maps:get(Key, Map, maps:get(BinKey, Map, undefined)).
