%% @doc Owner dashboard: current channel status (or a prompt to create one)
%% plus the clip list with publish/retract/archive actions -- the one entry
%% point every other owner-UI page links back to.
%% Route: GET /
-module(tube_dashboard_page).

-export([init/2, routes/0]).

routes() -> [{"/", ?MODULE, []}].

init(Req0, State) ->
    case cowboy_req:method(Req0) of
        <<"GET">> -> handle_get(Req0, State);
        _         -> tube_owner_http:method_not_allowed(Req0, State)
    end.

handle_get(Req0, State) ->
    Flash = flash_param(Req0),
    Body = tube_html:page(<<"Dashboard">>, render(project_tube_store:list_channels(), Flash)),
    tube_owner_http:reply_html(Body, Req0, State).

render([], Flash) ->
    [tube_html:flash_banner(Flash),
     <<"<h1>Welcome</h1>"
       "<p>You have not configured a channel yet.</p>"
       "<p><a class=\"button\" href=\"/owner/channel/configure\">"
       "Configure your channel</a></p>">>];
render([Channel | _], Flash) ->
    ChannelId = maps:get(channel_id, Channel, undefined),
    [tube_html:flash_banner(Flash),
     channel_card(Channel),
     <<"<h2>Video Clips</h2>"
       "<p><a class=\"button\" href=\"/owner/clips/upload\">Upload a clip</a></p>">>,
     clip_section(ChannelId)].

channel_card(Channel) ->
    Name = maps:get(name, Channel, undefined),
    Description = maps:get(description, Channel, undefined),
    Tags = maps:get(tags, Channel, []),
    [<<"<section class=\"card\"><h1>">>, tube_html:escape(Name), <<"</h1>"
       "<p>">>, tube_html:escape(Description), <<"</p>"
       "<p>">>, tag_spans(Tags), <<"</p>"
       "<p><a href=\"/owner/channel/configure\">Edit channel</a></p></section>">>].

tag_spans(Tags) ->
    [ [<<"<span class=\"tag\">">>, tube_html:escape(T), <<"</span>">>] || T <- Tags ].

clip_section(undefined) -> <<>>;
clip_section(ChannelId) ->
    case project_tube_store:list_clips_by_channel(ChannelId) of
        [] -> <<"<p class=\"empty\">No clips yet.</p>">>;
        Clips -> [<<"<div class=\"clip-grid\">">>, [clip_card(C) || C <- Clips], <<"</div>">>]
    end.

clip_card(Clip) ->
    ClipId = maps:get(clip_id, Clip, <<>>),
    Name = maps:get(name, Clip, undefined),
    Status = maps:get(status, Clip, <<"uploaded">>),
    ViewCount = maps:get(view_count, Clip, 0),
    [<<"<article class=\"card clip\"><h3>">>, tube_html:escape(Name), <<"</h3>"
       "<span class=\"status status-">>, Status, <<"\">">>, Status, <<"</span>"
       "<p class=\"muted\">">>, integer_to_binary(ViewCount), <<" views</p>"
       "<div class=\"actions\">">>, clip_actions(ClipId, Status), <<"</div></article>">>].

%% `ClipId'/`Status' are always system-generated (reckon_gater_stream_id /
%% this app's own projection), never user-supplied text -- safe to
%% interpolate directly, no escaping needed.
clip_actions(ClipId, <<"uploaded">>) ->
    [action_button(ClipId, <<"publish">>, <<"Publish">>, false),
     action_button(ClipId, <<"archive">>, <<"Discard">>, true)];
clip_actions(ClipId, <<"published">>) ->
    [action_button(ClipId, <<"retract">>, <<"Retract">>, false),
     action_button(ClipId, <<"archive">>, <<"Archive">>, true)];
clip_actions(_ClipId, _Archived) ->
    [<<"<span class=\"muted\">Archived</span>">>].

action_button(ClipId, Action, Label, Danger) ->
    Class = case Danger of true -> <<" class=\"danger\"">>; false -> <<>> end,
    [<<"<form method=\"post\" action=\"/owner/clips/">>, ClipId, <<"/">>, Action, <<"\">"
       "<button type=\"submit\"">>, Class, <<">">>, Label, <<"</button></form>">>].

flash_param(Req) ->
    proplists:get_value(<<"flash">>, cowboy_req:parse_qs(Req)).
