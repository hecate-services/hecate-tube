%% @doc Probes an uploaded video file for duration/dimensions/codec/
%% audio via `ffprobe', and derives a thumbnail frame via `ffmpeg' when
%% the owner didn't supply their own (theirs always wins). Called
%% synchronously from `maybe_upload_video_clip:handle/1' -- part of the
%% `upload_video_clip' command's own Chain of Responsibility, not a
%% separate async step. See plans/EVENT_STORM_HECATE_TUBE.md sec 16.4.
%%
%% Duration/metadata failure is fatal (the whole upload is rejected --
%% an unreadable file has nothing worth accepting). Thumbnail
%% extraction failure is NOT fatal: a valid video too short to seek
%% into, or a codec ffmpeg can decode but not frame-grab cleanly,
%% still gets accepted with `thumbnail_mcid = undefined' -- the realm
%% side falls back to a placeholder image for that case (sec 16.3).
%%
%% Both binaries run via `open_port({spawn_executable, ...})', never a
%% shell -- no injection surface regardless of file content, and
%% `LocalRef' is always this app's own randomly-generated filename
%% (tube_multipart:stream_to_file/2), never client-supplied text.
%% evoq's own dispatch call is `gen_server:call(Pid, ..., infinity)'
%% (evoq_aggregate.erl), so nothing evoq-side bounds how long this may
%% run -- the timeouts below are this module's own, so a corrupt or
%% adversarial file can't wedge the clip's aggregate process forever.
-module(video_clip_scan).

-export([probe/3]).

-define(FFPROBE, "ffprobe").
-define(FFMPEG, "ffmpeg").
-define(PROBE_TIMEOUT_MS, 15_000).
-define(THUMBNAIL_TIMEOUT_MS, 15_000).
-define(THUMBNAIL_SEEK, "00:00:01").

-spec probe(binary(), binary(), binary() | undefined) ->
    {ok, #{duration_ms := non_neg_integer(),
           width := non_neg_integer() | undefined,
           height := non_neg_integer() | undefined,
           codec := binary() | undefined,
           container_format := binary() | undefined,
           file_size_bytes := non_neg_integer(),
           has_audio := boolean(),
           thumbnail_mcid := binary() | undefined}} |
    {error, term()}.
probe(ClipId, LocalRef, ExistingThumbnailMcid) ->
    with_file_size(file_size(LocalRef), ClipId, LocalRef, ExistingThumbnailMcid).

with_file_size({ok, FileSizeBytes}, ClipId, LocalRef, ExistingThumbnailMcid) ->
    with_probe(ffprobe(LocalRef), ClipId, LocalRef, FileSizeBytes, ExistingThumbnailMcid);
with_file_size({error, _} = Error, _ClipId, _LocalRef, _ExistingThumbnailMcid) ->
    Error.

with_probe({ok, Probe}, ClipId, LocalRef, FileSizeBytes, ExistingThumbnailMcid) ->
    ThumbnailMcid = resolved_thumbnail_mcid(ClipId, LocalRef, ExistingThumbnailMcid),
    {ok, Probe#{file_size_bytes => FileSizeBytes, thumbnail_mcid => ThumbnailMcid}};
with_probe({error, _} = Error, _ClipId, _LocalRef, _FileSizeBytes, _ExistingThumbnailMcid) ->
    Error.

file_size(LocalRef) ->
    case filelib:is_regular(LocalRef) of
        true  -> {ok, filelib:file_size(LocalRef)};
        false -> {error, file_not_found}
    end.

%% ── Duration / dimensions / codec (fatal on failure) ──────────────

ffprobe(LocalRef) ->
    Args = ["-v", "error", "-print_format", "json",
            "-show_format", "-show_streams", binary_to_list(LocalRef)],
    with_probe_output(run(?FFPROBE, Args, ?PROBE_TIMEOUT_MS)).

with_probe_output({ok, Json}) -> parse_probe(Json);
with_probe_output({error, _} = Error) -> Error.

parse_probe(Json) -> with_decode(try_decode(Json)).

try_decode(Json) ->
    try {ok, jsx:decode(Json, [return_maps])}
    catch _:_ -> {error, invalid_probe_output}
    end.

with_decode({ok, Decoded}) -> from_probe_map(Decoded);
with_decode({error, _} = Error) -> Error.

from_probe_map(#{<<"format">> := Format} = Decoded) ->
    DurationMs = duration_ms(maps:get(<<"duration">>, Format, undefined)),
    Streams = maps:get(<<"streams">>, Decoded, []),
    VideoStream = find_stream(<<"video">>, Streams),
    HasAudio = find_stream(<<"audio">>, Streams) =/= undefined,
    with_duration(DurationMs, Format, VideoStream, HasAudio);
from_probe_map(_NoFormat) ->
    {error, no_format_in_probe_output}.

with_duration(undefined, _Format, _VideoStream, _HasAudio) ->
    {error, no_duration_in_probe_output};
with_duration(DurationMs, Format, VideoStream, HasAudio) ->
    {ok, #{
        duration_ms      => DurationMs,
        width             => stream_field(<<"width">>, VideoStream),
        height            => stream_field(<<"height">>, VideoStream),
        codec             => stream_field(<<"codec_name">>, VideoStream),
        container_format  => maps:get(<<"format_name">>, Format, undefined),
        has_audio         => HasAudio
    }}.

duration_ms(undefined) -> undefined;
duration_ms(DurationBin) when is_binary(DurationBin) ->
    try round(binary_to_float(DurationBin) * 1000)
    catch _:_ -> undefined
    end.

find_stream(_Type, []) -> undefined;
find_stream(Type, [#{<<"codec_type">> := Type} = Stream | _Rest]) -> Stream;
find_stream(Type, [_Stream | Rest]) -> find_stream(Type, Rest).

stream_field(_Key, undefined) -> undefined;
stream_field(Key, Stream) -> maps:get(Key, Stream, undefined).

%% ── Thumbnail (best-effort, never fails the upload) ────────────────

resolved_thumbnail_mcid(_ClipId, _LocalRef, ExistingMcid) when ExistingMcid =/= undefined ->
    ExistingMcid;
resolved_thumbnail_mcid(ClipId, LocalRef, undefined) ->
    thumbnail_mcid_from_frame(extract_frame(ClipId, LocalRef)).

thumbnail_mcid_from_frame({ok, Bytes}) -> with_put_result(tube_content_put:put(Bytes));
thumbnail_mcid_from_frame({error, _Reason}) -> undefined.

with_put_result({ok, Mcid}) -> Mcid;
with_put_result({error, _Reason}) -> undefined.

extract_frame(ClipId, LocalRef) ->
    OutPath = temp_thumbnail_path(ClipId),
    Args = ["-y", "-ss", ?THUMBNAIL_SEEK, "-i", binary_to_list(LocalRef),
            "-frames:v", "1", binary_to_list(OutPath)],
    with_extract_result(run(?FFMPEG, Args, ?THUMBNAIL_TIMEOUT_MS), OutPath).

with_extract_result({ok, _Stdout}, OutPath) ->
    read_and_delete(file:read_file(OutPath), OutPath);
with_extract_result({error, _} = Error, OutPath) ->
    _ = file:delete(OutPath),
    Error.

read_and_delete({ok, Bytes}, OutPath) ->
    _ = file:delete(OutPath),
    {ok, Bytes};
read_and_delete({error, Reason}, _OutPath) ->
    {error, {thumbnail_read_failed, Reason}}.

%% Scratch file only -- created, read, deleted within this one probe/3
%% call. `/tmp' is fine for that lifetime; no need for the durable
%% clips directory a CMD-department module can't reach anyway (that
%% path lives in hecate_tube, the web app, which depends on this app,
%% not the other way around).
temp_thumbnail_path(ClipId) ->
    filename:join(<<"/tmp">>, <<ClipId/binary, "-thumb.jpg">>).

%% ── Subprocess runner ───────────────────────────────────────────────

%% Resolved via PATH, not a hardcoded install location -- the alpine
%% runtime image, a glibc dev box, and CI's erlang:28 (debian) container
%% don't all put ffmpeg/ffprobe at the same path. A missing binary is an
%% ops/deployment bug, not a per-upload content problem, but it still
%% flows through the same {error, _} rejection path as any other scan
%% failure rather than crashing the aggregate on enoent -- consistent
%% with never letting an external command failure take the process down.
run(Executable, Args, TimeoutMs) ->
    with_resolved(os:find_executable(Executable), Args, TimeoutMs, Executable).

with_resolved(false, _Args, _TimeoutMs, Executable) ->
    {error, {executable_not_found, Executable}};
with_resolved(Path, Args, TimeoutMs, _Executable) ->
    Port = erlang:open_port({spawn_executable, Path},
                             [{args, Args}, exit_status, binary, stderr_to_stdout]),
    collect(Port, <<>>, TimeoutMs).

collect(Port, Acc, TimeoutMs) ->
    receive
        {Port, {data, Data}} ->
            collect(Port, <<Acc/binary, Data/binary>>, TimeoutMs);
        {Port, {exit_status, 0}} ->
            {ok, Acc};
        {Port, {exit_status, Code}} ->
            {error, {exit_status, Code, Acc}}
    after TimeoutMs ->
        catch erlang:port_close(Port),
        {error, timeout}
    end.
