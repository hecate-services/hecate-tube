%% @doc Event: video_clip_uploaded_v1.
-module(video_clip_uploaded_v1).

-behaviour(evoq_event).

-export([event_type/0, new/1, from_command/1, to_map/1]).
-export([clip_id/1]).

-record(video_clip_uploaded_v1, {
    clip_id        :: binary(),
    channel_id     :: binary(),
    name           :: binary(),
    description    :: binary(),
    tags           :: [binary()],
    thumbnail_mcid :: binary() | undefined,
    local_ref      :: binary(),
    source         :: binary(),
    uploaded_at    :: integer()
}).

-opaque t() :: #video_clip_uploaded_v1{}.
-export_type([t/0]).

event_type() -> <<"video_clip_uploaded_v1">>.

-spec new(map()) -> t().
new(#{clip_id := Id, channel_id := ChannelId, name := Name,
      description := Description, tags := Tags,
      thumbnail_mcid := ThumbnailMcid, local_ref := LocalRef,
      source := Source}) ->
    #video_clip_uploaded_v1{
        clip_id = Id,
        channel_id = ChannelId,
        name = Name,
        description = Description,
        tags = Tags,
        thumbnail_mcid = ThumbnailMcid,
        local_ref = LocalRef,
        source = Source,
        uploaded_at = erlang:system_time(millisecond)
    }.

-spec from_command(upload_video_clip_v1:t()) -> t().
from_command(Cmd) ->
    new(#{
        clip_id        => upload_video_clip_v1:clip_id(Cmd),
        channel_id     => upload_video_clip_v1:channel_id(Cmd),
        name           => upload_video_clip_v1:name(Cmd),
        description    => upload_video_clip_v1:description(Cmd),
        tags           => upload_video_clip_v1:tags(Cmd),
        thumbnail_mcid => upload_video_clip_v1:thumbnail_mcid(Cmd),
        local_ref      => upload_video_clip_v1:local_ref(Cmd),
        source         => upload_video_clip_v1:source(Cmd)
    }).

-spec to_map(t()) -> map().
to_map(#video_clip_uploaded_v1{} = E) ->
    #{
        event_type     => event_type(),
        clip_id        => E#video_clip_uploaded_v1.clip_id,
        channel_id     => E#video_clip_uploaded_v1.channel_id,
        name           => E#video_clip_uploaded_v1.name,
        description    => E#video_clip_uploaded_v1.description,
        tags           => E#video_clip_uploaded_v1.tags,
        thumbnail_mcid => E#video_clip_uploaded_v1.thumbnail_mcid,
        local_ref      => E#video_clip_uploaded_v1.local_ref,
        source         => E#video_clip_uploaded_v1.source,
        uploaded_at    => E#video_clip_uploaded_v1.uploaded_at
    }.

clip_id(#video_clip_uploaded_v1{clip_id = V}) -> V.
