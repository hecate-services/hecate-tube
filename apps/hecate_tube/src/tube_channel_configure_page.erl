%% @doc Owner UI: configure the channel (name/description/tags/logo). One
%% form serves both desks -- initiate_channel (no channel yet) and
%% reconfigure_channel (channel exists) -- since they share every field
%% except `owner', which only initiate takes and never changes after.
%% Route: GET/POST /owner/channel/configure
-module(tube_channel_configure_page).

-export([init/2, routes/0]).

routes() -> [{"/owner/channel/configure", ?MODULE, []}].

init(Req0, State) ->
    case cowboy_req:method(Req0) of
        <<"GET">>  -> handle_get(Req0, State);
        <<"POST">> -> handle_post(Req0, State);
        _          -> tube_owner_http:method_not_allowed(Req0, State)
    end.

handle_get(Req0, State) ->
    Flash = proplists:get_value(<<"flash">>, cowboy_req:parse_qs(Req0)),
    Body = tube_html:page(<<"Configure Channel">>, render_form(existing_channel(), Flash)),
    tube_owner_http:reply_html(Body, Req0, State).

handle_post(Req0, State) ->
    {Fields, Req1} = tube_multipart:read_fields(Req0, undefined),
    submit(existing_channel(), Fields, put_logo(maps:get(<<"logo">>, Fields, undefined)),
          Req1, State).

submit(Channel, Fields, {ok, LogoMcid}, Req1, State) ->
    dispatch_and_redirect(Channel, Fields, LogoMcid, Req1, State);
submit(_Channel, _Fields, {error, Reason}, Req1, State) ->
    tube_owner_http:redirect(<<"/owner/channel/configure">>,
        tube_owner_http:error_message(<<"Could not upload the logo: ">>, Reason), Req1, State).

dispatch_and_redirect(undefined, Fields, LogoMcid, Req1, State) ->
    Params = #{
        name        => maps:get(<<"name">>, Fields, <<>>),
        description => maps:get(<<"description">>, Fields, <<>>),
        owner       => maps:get(<<"owner">>, Fields, <<>>),
        tags        => tube_html:parse_tags(maps:get(<<"tags">>, Fields, undefined)),
        logo_mcid   => nonempty_or_undefined(LogoMcid)
    },
    reply_with_result(maybe_initiate_channel:dispatch(Params), Req1, State);
dispatch_and_redirect(Channel, Fields, LogoMcid, Req1, State) ->
    Params = #{
        channel_id  => maps:get(channel_id, Channel),
        name        => maps:get(<<"name">>, Fields, <<>>),
        description => maps:get(<<"description">>, Fields, <<>>),
        tags        => tube_html:parse_tags(maps:get(<<"tags">>, Fields, undefined)),
        logo_mcid   => logo_or_existing(LogoMcid, Channel)
    },
    reply_with_result(maybe_reconfigure_channel:dispatch(Params), Req1, State).

nonempty_or_undefined(undefined) -> undefined;
nonempty_or_undefined(Mcid) -> Mcid.

%% Keep the current logo unless a new one was uploaded.
logo_or_existing(undefined, Channel) -> maps:get(logo_mcid, Channel, undefined);
logo_or_existing(LogoMcid, _Channel) -> LogoMcid.

reply_with_result({ok, _ChannelId, _Version, _Events}, Req1, State) ->
    tube_owner_http:redirect(<<"/">>, <<"Channel saved.">>, Req1, State);
reply_with_result({ok, _Version, _Events}, Req1, State) ->
    tube_owner_http:redirect(<<"/">>, <<"Channel saved.">>, Req1, State);
reply_with_result({error, Reason}, Req1, State) ->
    tube_owner_http:redirect(<<"/owner/channel/configure">>,
        tube_owner_http:error_message(<<"Could not save the channel: ">>, Reason), Req1, State).

put_logo(undefined) -> {ok, undefined};
put_logo(<<>>) -> {ok, undefined};
put_logo(Bytes) -> tube_content_put:put(Bytes).

existing_channel() ->
    case project_tube_store:list_channels() of
        [Channel | _] -> Channel;
        []             -> undefined
    end.

render_form(undefined, Flash) ->
    form_shell(<<"Configure your channel">>, Flash, owner_field(<<>>), <<>>, <<>>, <<>>, undefined);
render_form(Channel, Flash) ->
    Name = maps:get(name, Channel, <<>>),
    Description = maps:get(description, Channel, <<>>),
    Tags = tube_html:format_tags(maps:get(tags, Channel, [])),
    LogoMcid = maps:get(logo_mcid, Channel, undefined),
    form_shell(<<"Edit your channel">>, Flash, <<>>, Name, Description, Tags, LogoMcid).

form_shell(Heading, Flash, OwnerField, Name, Description, Tags, LogoMcid) ->
    [tube_html:flash_banner(Flash),
     <<"<h1>">>, tube_html:escape(Heading), <<"</h1>"
       "<form class=\"owner-form\" method=\"post\" enctype=\"multipart/form-data\">">>,
     OwnerField,
     <<"<label for=\"name\">Channel name</label>"
       "<input type=\"text\" id=\"name\" name=\"name\" required value=\"">>,
     tube_html:escape(Name),
     <<"\">"
       "<label for=\"description\">Description</label>"
       "<textarea id=\"description\" name=\"description\">">>,
     tube_html:escape(Description),
     <<"</textarea>"
       "<label for=\"tags\">Tags</label>"
       "<input type=\"text\" id=\"tags\" name=\"tags\" value=\"">>,
     tube_html:escape(Tags),
     <<"\">"
       "<p class=\"hint\">Comma-separated, e.g. \"music, live, weekly\"</p>"
       "<label for=\"logo\">Logo</label>">>,
     current_logo(LogoMcid),
     <<"<input type=\"file\" id=\"logo\" name=\"logo\" accept=\"image/*\">"
       "<p class=\"hint\">Leave empty to keep the current logo.</p>"
       "<p><button type=\"submit\">Save</button></p>"
       "</form>">>].

current_logo(undefined) -> <<>>;
current_logo(Mcid) -> [<<"<p class=\"hint\">Current logo: ">>, tube_html:escape(Mcid), <<"</p>">>].

owner_field(Value) ->
    [<<"<label for=\"owner\">Owner</label>"
       "<input type=\"text\" id=\"owner\" name=\"owner\" required value=\"">>,
     tube_html:escape(Value), <<"\">">>].
