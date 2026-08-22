%% @doc Shared multipart/form-data reading for the owner UI's write forms.
%% Plain fields decode as their raw content (text fields as UTF-8
%% binaries); file fields are read fully into memory here too -- fine for
%% small things, a description, a logo or a thumbnail image -- EXCEPT the
%% one field the caller names as a stream target (the video file), which
%% is written straight to disk chunk by chunk instead of buffered, so a
%% multi-hundred-MB upload never has to sit whole in the node's memory.
-module(tube_multipart).

-export([read_fields/2]).

-define(CHUNK_OPTS, #{length => 262144}).

%% @doc `StreamSpec' is `{FieldName, Dir}' (both binaries) to stream that
%% one field's file content to a freshly-opened file under `Dir' instead
%% of buffering it -- its value in the returned map is the path written
%% to, not the bytes -- or `undefined' to buffer every field.
-spec read_fields(cowboy_req:req(), {binary(), binary()} | undefined) ->
    {#{binary() => binary()}, cowboy_req:req()}.
read_fields(Req0, StreamSpec) ->
    read_fields(Req0, StreamSpec, #{}).

read_fields(Req0, StreamSpec, Acc) ->
    case cowboy_req:read_part(Req0) of
        {ok, Headers, Req1} ->
            {FieldName, Value, Req2} = read_one(Headers, StreamSpec, Req1),
            read_fields(Req2, StreamSpec, Acc#{FieldName => Value});
        {done, Req1} ->
            {Acc, Req1}
    end.

read_one(Headers, {StreamField, StreamDir}, Req1) ->
    case cow_multipart:form_data(Headers) of
        {file, StreamField, _Filename, _Type} ->
            {Path, Req2} = stream_to_file(Req1, StreamDir),
            {StreamField, Path, Req2};
        FormData ->
            read_buffered(FormData, Req1)
    end;
read_one(Headers, undefined, Req1) ->
    read_buffered(cow_multipart:form_data(Headers), Req1).

read_buffered({file, FieldName, _Filename, _Type}, Req1) ->
    {Bytes, Req2} = read_body(Req1),
    {FieldName, Bytes, Req2};
read_buffered({data, FieldName}, Req1) ->
    {Bytes, Req2} = read_body(Req1),
    {FieldName, Bytes, Req2}.

read_body(Req0) ->
    read_body(Req0, <<>>).

read_body(Req0, Acc) ->
    case cowboy_req:read_part_body(Req0, ?CHUNK_OPTS) of
        {ok, Data, Req1} -> {<<Acc/binary, Data/binary>>, Req1};
        {more, Data, Req1} -> read_body(Req1, <<Acc/binary, Data/binary>>)
    end.

%% The client-supplied filename is NEVER used for the on-disk path -- that
%% is a path-traversal vector. A random name is enough; `local_ref' is an
%% opaque edge-local handle, nothing ever reads a filename back out of it.
stream_to_file(Req0, Dir) ->
    ok = filelib:ensure_dir(filename:join(Dir, <<"x">>)),
    Name = binary:encode_hex(crypto:strong_rand_bytes(16)),
    Path = filename:join(Dir, <<Name/binary, ".bin">>),
    {ok, Fd} = file:open(Path, [write, binary]),
    Req2 = stream_chunks(Req0, Fd),
    ok = file:close(Fd),
    {Path, Req2}.

stream_chunks(Req0, Fd) ->
    case cowboy_req:read_part_body(Req0, ?CHUNK_OPTS) of
        {ok, Data, Req1} -> ok = file:write(Fd, Data), Req1;
        {more, Data, Req1} -> ok = file:write(Fd, Data), stream_chunks(Req1, Fd)
    end.
