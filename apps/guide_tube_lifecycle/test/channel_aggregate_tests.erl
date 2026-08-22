%% @doc Pure unit tests for the channel and video_clip aggregate/handler/
%% state cycles -- no live evoq dispatch, no store. Mirrors
%% hecate-mpong-bot's test/*_tests.erl shape.
-module(channel_aggregate_tests).

-include_lib("eunit/include/eunit.hrl").

%%% channel

initiate_channel_mints_a_valid_stream_id_test() ->
    {ok, Cmd} = initiate_channel_v1:new(#{name => <<"Rafael">>, owner => <<"acme">>}),
    ChannelId = initiate_channel_v1:channel_id(Cmd),
    ?assertEqual(ok, reckon_gater_stream_id:validate(ChannelId)),
    ?assertMatch({user, <<"channel">>, _}, reckon_gater_stream_id:parts(ChannelId)).

initiate_channel_rejects_missing_fields_test() ->
    ?assertEqual({error, name_and_owner_required}, initiate_channel_v1:new(#{name => <<"x">>})),
    ?assertEqual({error, name_and_owner_required}, initiate_channel_v1:new(#{owner => <<"x">>})),
    ?assertEqual({error, name_and_owner_required},
                 initiate_channel_v1:new(#{name => <<>>, owner => <<"x">>})).

channel_aggregate_allows_initiate_on_fresh_state_test() ->
    ChannelId = reckon_gater_stream_id:new(<<"channel">>),
    {ok, State} = channel_aggregate:init(ChannelId),
    Payload = #{command_type => initiate_channel, channel_id => ChannelId,
                name => <<"Rafael">>, description => <<"desc">>, owner => <<"acme">>,
                tags => [<<"music">>], logo_mcid => undefined},
    {ok, [Event]} = channel_aggregate:execute(State, Payload),
    ?assertEqual(<<"channel_initiated_v1">>, maps:get(event_type, Event)),
    ?assertEqual(ChannelId, maps:get(channel_id, Event)),

    NewState = channel_aggregate:apply(State, Event),
    ?assertEqual(1, channel_state:status(NewState)),
    ?assertEqual(<<"Rafael">>, channel_state:name(NewState)),
    ?assertEqual(<<"acme">>, channel_state:owner(NewState)).

channel_aggregate_rejects_double_initiate_test() ->
    ChannelId = reckon_gater_stream_id:new(<<"channel">>),
    {ok, Fresh} = channel_aggregate:init(ChannelId),
    Payload = #{command_type => initiate_channel, channel_id => ChannelId,
                name => <<"Rafael">>, description => <<>>, owner => <<"acme">>,
                tags => [], logo_mcid => undefined},
    {ok, [Event]} = channel_aggregate:execute(Fresh, Payload),
    Initiated = channel_aggregate:apply(Fresh, Event),

    ?assertEqual({error, already_initiated},
                 channel_aggregate:execute(Initiated, Payload)).

channel_aggregate_rejects_reconfigure_before_initiate_test() ->
    ChannelId = reckon_gater_stream_id:new(<<"channel">>),
    {ok, Fresh} = channel_aggregate:init(ChannelId),
    Payload = #{command_type => reconfigure_channel, channel_id => ChannelId,
                name => <<"New name">>, description => <<>>, tags => [],
                logo_mcid => undefined},
    ?assertEqual({error, not_initiated}, channel_aggregate:execute(Fresh, Payload)).

channel_aggregate_allows_reconfigure_after_initiate_test() ->
    ChannelId = reckon_gater_stream_id:new(<<"channel">>),
    {ok, Fresh} = channel_aggregate:init(ChannelId),
    InitPayload = #{command_type => initiate_channel, channel_id => ChannelId,
                    name => <<"Rafael">>, description => <<>>, owner => <<"acme">>,
                    tags => [], logo_mcid => undefined},
    {ok, [InitEvent]} = channel_aggregate:execute(Fresh, InitPayload),
    Initiated = channel_aggregate:apply(Fresh, InitEvent),

    ReconfPayload = #{command_type => reconfigure_channel, channel_id => ChannelId,
                      name => <<"New name">>, description => <<"new desc">>,
                      tags => [<<"tag">>], logo_mcid => <<"mcid-1">>},
    {ok, [ReconfEvent]} = channel_aggregate:execute(Initiated, ReconfPayload),
    ?assertEqual(<<"channel_reconfigured_v1">>, maps:get(event_type, ReconfEvent)),

    Reconfigured = channel_aggregate:apply(Initiated, ReconfEvent),
    ?assertEqual(<<"New name">>, channel_state:name(Reconfigured)),
    %% owner survives reconfigure unchanged -- it's not in the desk's payload
    ?assertEqual(<<"acme">>, channel_state:owner(Reconfigured)).

channel_projection_writes_the_store_facade_test() ->
    %% eunit discovers this suite both under its owning module and by its
    %% own name in one VM, running this test twice -- tolerate the store
    %% already being up from the first pass.
    ensure_started(project_tube_store:start_link()),
    ChannelId = reckon_gater_stream_id:new(<<"channel">>),
    %% Matches evoq_store_subscription:evoq_event_to_routable/1's actual
    %% shape: the event's own fields live under `data', not top-level.
    Event = #{event_type => <<"channel_initiated_v1">>,
              data => #{channel_id => ChannelId, name => <<"Rafael">>,
                        description => <<>>, owner => <<"acme">>, tags => [],
                        logo_mcid => undefined,
                        initiated_at => erlang:system_time(millisecond)}},
    {ok, RM} = evoq_read_model:new(evoq_read_model_ets, #{name => test_channels_projection}),
    {ok, _State, _RM2} = channel_lifecycle_to_channels:project(Event, #{}, #{}, RM),

    {ok, Row} = project_tube_store:get_channel(ChannelId),
    ?assertEqual(<<"Rafael">>, maps:get(name, Row)).

%%% video_clip

upload_video_clip_mints_a_valid_stream_id_test() ->
    {ok, Cmd} = upload_video_clip_v1:new(#{channel_id => <<"channel-1">>,
                                           name => <<"My Clip">>,
                                           local_ref => <<"/data/clip1.mp4">>}),
    ClipId = upload_video_clip_v1:clip_id(Cmd),
    ?assertEqual(ok, reckon_gater_stream_id:validate(ClipId)),
    ?assertMatch({user, <<"clip">>, _}, reckon_gater_stream_id:parts(ClipId)),
    ?assertEqual(<<"uploaded">>, upload_video_clip_v1:source(Cmd)).

upload_video_clip_rejects_missing_fields_test() ->
    ?assertEqual({error, channel_id_name_and_local_ref_required},
                 upload_video_clip_v1:new(#{name => <<"x">>})).

%% `local_ref' points at a real, tiny (2KB, 1s, 32x32, h264, no audio)
%% fixture -- video_clip_scan:probe/3 genuinely shells out to ffprobe/
%% ffmpeg here, same as it does in production, not a stub. Confirms
%% the scan step doesn't just compile but actually accepts a real
%% file. See video_clip_upload_rejects_unreadable_file_test/0 below
%% for the rejection path.
-define(FIXTURE_CLIP, <<"apps/guide_tube_lifecycle/test/fixtures/tiny_clip.mp4">>).

video_clip_aggregate_lifecycle_test() ->
    ClipId = reckon_gater_stream_id:new(<<"clip">>),
    {ok, Fresh} = video_clip_aggregate:init(ClipId),
    UploadPayload = #{command_type => upload_video_clip, clip_id => ClipId,
                      channel_id => <<"channel-1">>, name => <<"My Clip">>,
                      description => <<>>, tags => [], thumbnail_mcid => undefined,
                      local_ref => ?FIXTURE_CLIP, source => <<"uploaded">>},
    {ok, [UploadedEvent, ScannedEvent, AcceptedEvent]} =
        video_clip_aggregate:execute(Fresh, UploadPayload),
    ?assertEqual(<<"video_clip_uploaded_v1">>, maps:get(event_type, UploadedEvent)),
    ?assertEqual(<<"video_clip_scanned_v1">>, maps:get(event_type, ScannedEvent)),
    ?assertEqual(1000, maps:get(duration_ms, ScannedEvent)),
    ?assertEqual(<<"video_clip_accepted_v1">>, maps:get(event_type, AcceptedEvent)),
    Uploaded0 = video_clip_aggregate:apply(Fresh, UploadedEvent),
    Uploaded1 = video_clip_aggregate:apply(Uploaded0, ScannedEvent),
    Uploaded = video_clip_aggregate:apply(Uploaded1, AcceptedEvent),
    ?assertEqual(1, video_clip_state:status(Uploaded)),

    %% Cannot re-upload an already-uploaded clip
    ?assertEqual({error, already_uploaded}, video_clip_aggregate:execute(Uploaded, UploadPayload)),

    PublishPayload = #{command_type => publish_video_clip, clip_id => ClipId,
                       channel_id => <<"channel-1">>},
    {ok, [PublishedEvent]} = video_clip_aggregate:execute(Uploaded, PublishPayload),
    Published = video_clip_aggregate:apply(Uploaded, PublishedEvent),
    ?assertEqual(3, video_clip_state:status(Published)), %% UPLOADED bor PUBLISHED

    %% Cannot publish twice
    ?assertEqual({error, cannot_publish}, video_clip_aggregate:execute(Published, PublishPayload)),

    %% A published clip can be viewed
    ViewPayload = #{command_type => record_video_clip_view, clip_id => ClipId,
                    channel_id => <<"channel-1">>, viewer_ref => undefined},
    ?assertMatch({ok, [_]}, video_clip_aggregate:execute(Published, ViewPayload)),

    RetractPayload = #{command_type => retract_video_clip, clip_id => ClipId,
                       channel_id => <<"channel-1">>},
    {ok, [RetractedEvent]} = video_clip_aggregate:execute(Published, RetractPayload),
    Retracted = video_clip_aggregate:apply(Published, RetractedEvent),
    ?assertEqual(1, video_clip_state:status(Retracted)), %% back to UPLOADED only

    %% A retracted (unpublished) clip cannot be viewed
    ?assertEqual({error, not_published}, video_clip_aggregate:execute(Retracted, ViewPayload)),

    ArchivePayload = #{command_type => archive_video_clip, clip_id => ClipId,
                       channel_id => <<"channel-1">>},
    {ok, [ArchivedEvent]} = video_clip_aggregate:execute(Retracted, ArchivePayload),
    Archived = video_clip_aggregate:apply(Retracted, ArchivedEvent),
    ?assertEqual(5, video_clip_state:status(Archived)), %% UPLOADED bor ARCHIVED

    %% Cannot archive twice
    ?assertEqual({error, already_archived}, video_clip_aggregate:execute(Archived, ArchivePayload)).

%% An unreadable/nonexistent file rejects the whole upload -- `uploaded'
%% still fires (bytes were genuinely never going to exist here since
%% the path itself is bogus, but the command was validly processed),
%% no `scanned' event (no real measurements), and the clip can never
%% be published afterward.
video_clip_upload_rejects_unreadable_file_test() ->
    ClipId = reckon_gater_stream_id:new(<<"clip">>),
    {ok, Fresh} = video_clip_aggregate:init(ClipId),
    UploadPayload = #{command_type => upload_video_clip, clip_id => ClipId,
                      channel_id => <<"channel-1">>, name => <<"Bad Clip">>,
                      description => <<>>, tags => [], thumbnail_mcid => undefined,
                      local_ref => <<"/nonexistent/nope.mp4">>, source => <<"uploaded">>},
    {ok, [UploadedEvent, RejectedEvent]} = video_clip_aggregate:execute(Fresh, UploadPayload),
    ?assertEqual(<<"video_clip_uploaded_v1">>, maps:get(event_type, UploadedEvent)),
    ?assertEqual(<<"video_clip_rejected_v1">>, maps:get(event_type, RejectedEvent)),
    ?assertEqual(<<"file_not_found">>, maps:get(reason, RejectedEvent)),
    Uploaded = video_clip_aggregate:apply(Fresh, UploadedEvent),
    Rejected = video_clip_aggregate:apply(Uploaded, RejectedEvent),
    ?assertEqual(9, video_clip_state:status(Rejected)), %% UPLOADED bor REJECTED

    PublishPayload = #{command_type => publish_video_clip, clip_id => ClipId,
                       channel_id => <<"channel-1">>},
    ?assertEqual({error, cannot_publish},
                 video_clip_aggregate:execute(Rejected, PublishPayload)).

video_clip_projection_writes_the_store_facade_test() ->
    ensure_started(project_tube_store:start_link()),
    ClipId = reckon_gater_stream_id:new(<<"clip">>),
    UploadedEvent = #{event_type => <<"video_clip_uploaded_v1">>,
                      data => #{clip_id => ClipId, channel_id => <<"channel-1">>,
                                name => <<"My Clip">>, description => <<>>,
                                tags => [], thumbnail_mcid => undefined,
                                local_ref => <<"/data/clip1.mp4">>,
                                source => <<"uploaded">>,
                                uploaded_at => erlang:system_time(millisecond)}},
    {ok, RM} = evoq_read_model:new(evoq_read_model_ets, #{name => test_video_clips_projection}),
    {ok, _State, RM2} = video_clip_lifecycle_to_video_clips:project(UploadedEvent, #{}, #{}, RM),

    {ok, Row} = project_tube_store:get_clip(ClipId),
    ?assertEqual(<<"My Clip">>, maps:get(name, Row)),
    ?assertEqual(<<"uploaded">>, maps:get(status, Row)),
    ?assertEqual(0, maps:get(view_count, Row)),

    PublishedEvent = #{event_type => <<"video_clip_published_v1">>,
                       data => #{clip_id => ClipId, channel_id => <<"channel-1">>,
                                 published_at => erlang:system_time(millisecond)}},
    {ok, _State2, _RM3} = video_clip_lifecycle_to_video_clips:project(PublishedEvent, #{}, #{}, RM2),
    {ok, PublishedRow} = project_tube_store:get_clip(ClipId),
    ?assertEqual(<<"published">>, maps:get(status, PublishedRow)),

    ViewedEvent = #{event_type => <<"video_clip_viewed_v1">>,
                    data => #{clip_id => ClipId, channel_id => <<"channel-1">>,
                              viewed_at => erlang:system_time(millisecond),
                              viewer_ref => undefined}},
    {ok, _State3, _RM4} = video_clip_lifecycle_to_video_clips:project(ViewedEvent, #{}, #{}, RM2),
    {ok, ViewedRow} = project_tube_store:get_clip(ClipId),
    ?assertEqual(1, maps:get(view_count, ViewedRow)).

ensure_started({ok, _Pid}) -> ok;
ensure_started({error, {already_started, _Pid}}) -> ok.
