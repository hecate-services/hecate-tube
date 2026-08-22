%% @doc Command: initiate_channel_v1 -- opens a channel's dossier.
-module(initiate_channel_v1).

-behaviour(evoq_command).

-export([command_type/0, new/1, to_map/1, from_map/1]).
-export([channel_id/1, name/1, description/1, owner/1, tags/1, logo_mcid/1]).

-record(initiate_channel_v1, {
    channel_id  :: binary(),
    name        :: binary(),
    description :: binary(),
    owner       :: binary(),
    tags        :: [binary()],
    logo_mcid   :: binary() | undefined
}).

-opaque t() :: #initiate_channel_v1{}.
-export_type([t/0]).

command_type() -> initiate_channel.

%% Mints the channel's id here, via reckon_gater_stream_id:new/1 -- not
%% supplied by the caller -- so it is both a valid entity id and a valid
%% stream id from the moment it exists. `description'/`tags'/`logo_mcid'
%% default to empty/undefined so an owner can open a channel with just a
%% name and owner and fill the rest in via reconfigure_channel later.
-spec new(map()) -> {ok, t()} | {error, term()}.
new(#{name := Name, owner := Owner} = Params)
  when is_binary(Name), Name =/= <<>>, is_binary(Owner), Owner =/= <<>> ->
    {ok, #initiate_channel_v1{
        channel_id  = reckon_gater_stream_id:new(<<"channel">>),
        name        = Name,
        description = maps:get(description, Params, <<>>),
        owner       = Owner,
        tags        = maps:get(tags, Params, []),
        logo_mcid   = maps:get(logo_mcid, Params, undefined)
    }};
new(_) ->
    {error, name_and_owner_required}.

-spec to_map(t()) -> map().
to_map(#initiate_channel_v1{} = Cmd) ->
    #{
        command_type => command_type(),
        channel_id   => Cmd#initiate_channel_v1.channel_id,
        name         => Cmd#initiate_channel_v1.name,
        description  => Cmd#initiate_channel_v1.description,
        owner        => Cmd#initiate_channel_v1.owner,
        tags         => Cmd#initiate_channel_v1.tags,
        logo_mcid    => Cmd#initiate_channel_v1.logo_mcid
    }.

%% Reconstructs a typed command from the plain map the aggregate receives
%% as its command payload (built via to_map/1 by maybe_initiate_channel).
-spec from_map(map()) -> {ok, t()} | {error, term()}.
from_map(#{channel_id := Id, name := Name, description := Description,
          owner := Owner, tags := Tags, logo_mcid := LogoMcid}) ->
    {ok, #initiate_channel_v1{channel_id = Id, name = Name,
                              description = Description, owner = Owner,
                              tags = Tags, logo_mcid = LogoMcid}};
from_map(_) ->
    {error, missing_required_fields}.

channel_id(#initiate_channel_v1{channel_id = V}) -> V.
name(#initiate_channel_v1{name = V}) -> V.
description(#initiate_channel_v1{description = V}) -> V.
owner(#initiate_channel_v1{owner = V}) -> V.
tags(#initiate_channel_v1{tags = V}) -> V.
logo_mcid(#initiate_channel_v1{logo_mcid = V}) -> V.
