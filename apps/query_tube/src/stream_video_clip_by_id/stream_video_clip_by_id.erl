%% @doc Streaming provider: tube.watch_video_clip. Streams a published
%% clip's bytes off local disk, chunk by chunk -- the mesh Content
%% primitive is never the video-bytes path (spec sec 3, "streamed, not
%% downloaded"). Refuses an unpublished/nonexistent clip via
%% handle_open/2's ordinary {stop, Reason, State} contract -- no
%% workaround needed; macula-io/macula's own bug on that path (StreamPid
%% never aborted, peer stranded until its own recv timeout) is fixed at
%% the source, see macula's CHANGELOG.
-module(stream_video_clip_by_id).

-behaviour(macula_streamer).

-export([init/1, handle_open/2]).

-define(CHUNK_BYTES, 65536).

init(_Args) -> {ok, undefined}.

%% `clip_id' arrives as an atom key, not a binary -- macula's frame
%% decoder round-trips any map key through binary_to_existing_atom/1
%% when the receiving VM already knows that atom (it does here; see
%% project_tube_store's own row shape), so the wire's `#{clip_id =>
%% ...}` never decodes to `#{<<"clip_id">> => ...}'. Confirmed live
%% via macula_frame:stream_open/1 + encode/1 + decode/1 round-trip.
handle_open(#{clip_id := ClipId}, State) ->
    open_from(project_tube_store:get_clip(ClipId), ClipId, State);
handle_open(_StreamArgs, State) ->
    {stop, bad_request, State}.

open_from({ok, #{status := <<"published">>, local_ref := LocalRef} = Row}, ClipId, State) ->
    stream_file(LocalRef, ClipId, maps:get(channel_id, Row, undefined), State);
open_from({ok, _NotPublished}, _ClipId, State) ->
    {stop, not_found, State};
open_from({error, not_found}, _ClipId, State) ->
    {stop, not_found, State}.

stream_file(LocalRef, ClipId, ChannelId, State) ->
    open_result(file:open(LocalRef, [read, binary]), ClipId, ChannelId, State).

open_result({ok, Fd}, ClipId, ChannelId, State) ->
    spawn_sender(self(), Fd, ClipId, ChannelId),
    {ok, State};
open_result({error, _Reason}, _ClipId, _ChannelId, State) ->
    {stop, not_found, State}.

%% Sending is push-based and driven from OUTSIDE handle_open/2, per
%% macula_streamer's own contract -- calling send/2 from inside
%% handle_open/2 is a gen_server self-call during its own init and
%% deadlocks (Demon #35). This helper process reads the file and pushes
%% chunks on the streamer's behalf, then records the view and closes.
spawn_sender(StreamerPid, Fd, ClipId, ChannelId) ->
    spawn(fun() -> send_chunks(StreamerPid, Fd, ClipId, ChannelId) end).

send_chunks(StreamerPid, Fd, ClipId, ChannelId) ->
    deliver(file:read(Fd, ?CHUNK_BYTES), StreamerPid, Fd, ClipId, ChannelId).

deliver({ok, Chunk}, StreamerPid, Fd, ClipId, ChannelId) ->
    ok = macula_streamer:send(StreamerPid, Chunk),
    send_chunks(StreamerPid, Fd, ClipId, ChannelId);
deliver(eof, StreamerPid, Fd, ClipId, ChannelId) ->
    _ = file:close(Fd),
    record_view(ClipId, ChannelId),
    ok = macula_streamer:close(StreamerPid);
deliver({error, _Reason}, StreamerPid, Fd, _ClipId, _ChannelId) ->
    _ = file:close(Fd),
    ok = macula_streamer:close(StreamerPid).

record_view(ClipId, ChannelId) ->
    maybe_record_video_clip_view:dispatch(#{clip_id => ClipId, channel_id => ChannelId}).
