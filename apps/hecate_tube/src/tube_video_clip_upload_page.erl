%% @doc Owner UI: upload a video clip (private, local-only at this point --
%% publishing is a separate, explicit action). The video itself is
%% streamed straight to disk as it's received (see tube_multipart), never
%% buffered whole in memory; the thumbnail, if any, is small enough to
%% buffer and goes through Content (macula_feeder) like the channel logo.
%%
%% `maybe_upload_video_clip:dispatch/1' scans the file synchronously as
%% part of handling the command (video_clip_scan.erl) -- this request
%% blocks for that too, same as it already blocks for the multipart
%% upload itself. A rejected scan is still an `{ok, ...}' dispatch
%% result (a recorded verdict, not a command failure), so the events
%% list has to be inspected to tell a rejection from a clean accept.
%% Route: GET/POST /owner/clips/upload
-module(tube_video_clip_upload_page).

-export([init/2, routes/0]).

routes() -> [{"/owner/clips/upload", ?MODULE, []}].

init(Req0, State) ->
    case cowboy_req:method(Req0) of
        <<"GET">>  -> handle_get(Req0, State);
        <<"POST">> -> handle_post(Req0, State);
        _          -> tube_owner_http:method_not_allowed(Req0, State)
    end.

handle_get(Req0, State) ->
    with_channel(existing_channel(), Req0, State, fun(_Channel) ->
        Flash = proplists:get_value(<<"flash">>, cowboy_req:parse_qs(Req0)),
        Body = tube_html:page(<<"Upload a Clip">>, render_form(Flash)),
        tube_owner_http:reply_html(Body, Req0, State)
    end).

handle_post(Req0, State) ->
    with_channel(existing_channel(), Req0, State, fun(Channel) ->
        do_upload(Channel, Req0, State)
    end).

with_channel(undefined, Req0, State, _Fun) ->
    tube_owner_http:redirect(<<"/owner/channel/configure">>,
        <<"Configure your channel before uploading a clip.">>, Req0, State);
with_channel(Channel, _Req0, _State, Fun) ->
    Fun(Channel).

do_upload(Channel, Req0, State) ->
    ClipsDir = filename:join(iolist_to_binary(hecate_tube_service:data_dir()), <<"clips">>),
    {Fields, Req1} = tube_multipart:read_fields(Req0, {<<"video">>, ClipsDir}),
    ChannelId = maps:get(channel_id, Channel),
    submit(ChannelId, Fields, put_thumbnail(maps:get(<<"thumbnail">>, Fields, undefined)),
          Req1, State).

submit(ChannelId, Fields, {ok, ThumbnailMcid}, Req1, State) ->
    dispatch(ChannelId, Fields, ThumbnailMcid, Req1, State);
submit(_ChannelId, _Fields, {error, Reason}, Req1, State) ->
    tube_owner_http:redirect(<<"/owner/clips/upload">>,
        tube_owner_http:error_message(<<"Could not upload the thumbnail: ">>, Reason), Req1, State).

dispatch(ChannelId, Fields, ThumbnailMcid, Req1, State) ->
    Params = #{
        channel_id     => ChannelId,
        name           => maps:get(<<"name">>, Fields, <<>>),
        description    => maps:get(<<"description">>, Fields, <<>>),
        tags           => tube_html:parse_tags(maps:get(<<"tags">>, Fields, undefined)),
        thumbnail_mcid => ThumbnailMcid,
        local_ref      => maps:get(<<"video">>, Fields, <<>>)
    },
    reply_with_result(maybe_upload_video_clip:dispatch(Params), Req1, State).

put_thumbnail(undefined) -> {ok, undefined};
put_thumbnail(<<>>) -> {ok, undefined};
put_thumbnail(Bytes) -> tube_content_put:put(Bytes).

reply_with_result({ok, _ClipId, _Version, Events}, Req1, State) ->
    reply_for_verdict(rejection_reason(Events), Req1, State);
reply_with_result({error, Reason}, Req1, State) ->
    tube_owner_http:redirect(<<"/owner/clips/upload">>,
        tube_owner_http:error_message(<<"Could not upload the clip: ">>, Reason), Req1, State).

reply_for_verdict(undefined, Req1, State) ->
    tube_owner_http:redirect(<<"/">>, <<"Clip uploaded, private until you publish it.">>,
                             Req1, State);
reply_for_verdict(Reason, Req1, State) ->
    %% Not tube_owner_http:error_message/2 -- Reason is already a
    %% clean, human-formatted binary (video_clip_rejected_v1's own
    %% reason_to_binary/1), and error_message/2's `~p' formatting
    %% would wrap it in visible `<<"...">>' quoting.
    Message = iolist_to_binary([<<"Video rejected: ">>, Reason]),
    tube_owner_http:redirect(<<"/owner/clips/upload">>, Message, Req1, State).

rejection_reason(Events) ->
    reason_from(lists:filter(fun is_rejected_event/1, Events)).

is_rejected_event(Event) ->
    maps:get(event_type, Event, undefined) =:= <<"video_clip_rejected_v1">>.

reason_from([#{reason := Reason} | _]) -> Reason;
reason_from([]) -> undefined.

existing_channel() ->
    case project_tube_store:list_channels() of
        [Channel | _] -> Channel;
        []             -> undefined
    end.

render_form(Flash) ->
    [tube_html:flash_banner(Flash),
     <<"<h1>Upload a video clip</h1>"
       "<p class=\"hint\">Uploading is private -- publish separately when you're ready.</p>"
       "<form class=\"owner-form\" method=\"post\" enctype=\"multipart/form-data\">"
       "<label for=\"name\">Title</label>"
       "<input type=\"text\" id=\"name\" name=\"name\" required>"
       "<label for=\"description\">Description</label>"
       "<textarea id=\"description\" name=\"description\"></textarea>"
       "<label for=\"tags\">Tags</label>"
       "<input type=\"text\" id=\"tags\" name=\"tags\">"
       "<p class=\"hint\">Comma-separated.</p>"
       "<label for=\"thumbnail\">Thumbnail</label>"
       "<input type=\"file\" id=\"thumbnail\" name=\"thumbnail\" accept=\"image/*\">"
       "<label for=\"video\">Video file</label>"
       "<input type=\"file\" id=\"video\" name=\"video\" accept=\"video/*\" required>"
       "<p><button type=\"submit\">Upload</button></p>"
       "</form>">>].
