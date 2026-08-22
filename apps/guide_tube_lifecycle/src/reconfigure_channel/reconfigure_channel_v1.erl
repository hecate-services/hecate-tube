%% @doc Command: reconfigure_channel_v1 -- covers the owner's "configure
%% the channel" action in full (name/description/tags/logo). CRUD-taboo
%% naming: this is `update_config' spelled the Hecate way, one desk for
%% every field rather than one desk per field.
-module(reconfigure_channel_v1).

-behaviour(evoq_command).

-export([command_type/0, new/1, to_map/1, from_map/1]).
-export([channel_id/1, name/1, description/1, tags/1, logo_mcid/1]).

-record(reconfigure_channel_v1, {
    channel_id  :: binary(),
    name        :: binary(),
    description :: binary(),
    tags        :: [binary()],
    logo_mcid   :: binary() | undefined
}).

-opaque t() :: #reconfigure_channel_v1{}.
-export_type([t/0]).

command_type() -> reconfigure_channel.

-spec new(map()) -> {ok, t()} | {error, term()}.
new(#{channel_id := Id, name := Name} = Params)
  when is_binary(Id), Id =/= <<>>, is_binary(Name), Name =/= <<>> ->
    {ok, #reconfigure_channel_v1{
        channel_id  = Id,
        name        = Name,
        description = maps:get(description, Params, <<>>),
        tags        = maps:get(tags, Params, []),
        logo_mcid   = maps:get(logo_mcid, Params, undefined)
    }};
new(_) ->
    {error, channel_id_and_name_required}.

-spec to_map(t()) -> map().
to_map(#reconfigure_channel_v1{} = Cmd) ->
    #{
        command_type => command_type(),
        channel_id   => Cmd#reconfigure_channel_v1.channel_id,
        name         => Cmd#reconfigure_channel_v1.name,
        description  => Cmd#reconfigure_channel_v1.description,
        tags         => Cmd#reconfigure_channel_v1.tags,
        logo_mcid    => Cmd#reconfigure_channel_v1.logo_mcid
    }.

-spec from_map(map()) -> {ok, t()} | {error, term()}.
from_map(#{channel_id := Id, name := Name, description := Description,
          tags := Tags, logo_mcid := LogoMcid}) ->
    {ok, #reconfigure_channel_v1{channel_id = Id, name = Name,
                                 description = Description, tags = Tags,
                                 logo_mcid = LogoMcid}};
from_map(_) ->
    {error, missing_required_fields}.

channel_id(#reconfigure_channel_v1{channel_id = V}) -> V.
name(#reconfigure_channel_v1{name = V}) -> V.
description(#reconfigure_channel_v1{description = V}) -> V.
tags(#reconfigure_channel_v1{tags = V}) -> V.
logo_mcid(#reconfigure_channel_v1{logo_mcid = V}) -> V.
