%%% ====================================================================
%%% ``The contents of this file are subject to the Erlang Public License,
%%% Version 1.1, (the "License"); you may not use this file except in
%%% compliance with the License. You should have received a copy of the
%%% Erlang Public License along with this software. If not, it can be
%%% retrieved via the world wide web at http://www.erlang.org/.
%%% 
%%% Software distributed under the License is distributed on an "AS IS"
%%% basis, WITHOUT WARRANTY OF ANY KIND, either express or implied. See
%%% the License for the specific language governing rights and limitations
%%% under the License.
%%% 
%%% The Initial Developer of the Original Code is ProcessOne.
%%% Portions created by ProcessOne are Copyright 2006-2010, ProcessOne
%%% All Rights Reserved.''
%%% This software is copyright 2006-2010, ProcessOne.
%%%
%%%
%%% @copyright 2006-2010 ProcessOne
%%% @author Christophe Romain <christophe.romain@process-one.net>
%%%   [http://www.process-one.net/]
%%% @version {@vsn}, {@date} {@time}
%%% @end
%%% ====================================================================

%%% @doc The module <strong>{@module}</strong> is the pep PubSub plugin.
%%% <p>PubSub plugin nodes are using the {@link gen_pubsub_node} behaviour.</p>

-module(node_pep).
-author('christophe.romain@process-one.net').

-include("ejabberd.hrl").
-include("pubsub.hrl").

-behaviour(gen_pubsub_node).

%% API definition
-export([init/3, terminate/2,
	 options/0, features/0,
	 create_node_permission/6,
	 create_node/2,
	 delete_node/1,
	 purge_node/2,
	 subscribe_node/8,
	 unsubscribe_node/4,
	 publish_item/6,
	 delete_item/4,
	 remove_extra_items/3,
	 get_entity_affiliations/2,
	 get_node_affiliations/1,
	 get_affiliation/2,
	 set_affiliation/3,
	 get_entity_subscriptions/2,
	 get_node_subscriptions/1,
	 get_subscriptions/2,
	 set_subscriptions/4,
	 get_pending_nodes/2,
	 get_states/1,
	 get_state/2,
	 set_state/1,
	 get_items/6,
	 get_items/2,
	 get_item/7,
	 get_item/2,
	 set_item/1,
	 get_item_name/3,
	 node_to_path/1,
	 path_to_node/1
	]).

init(Host, ServerHost, Opts) ->
    node_flat:init(Host, ServerHost, Opts),
    complain_if_modcaps_disabled(ServerHost),
    ok.

terminate(Host, ServerHost) ->
    node_flat:terminate(Host, ServerHost),
    ok.

options() ->
    [{deliver_payloads, true},
     {notify_config, false},
     {notify_delete, false},
     {notify_retract, false},
     {notify_sub, false},
     {purge_offline, false},
     {persist_items, false},
     {max_items, ?MAXITEMS},
     {subscribe, true},
     {access_model, presence},
     {roster_groups_allowed, []},
     {publish_model, publishers},
     {notification_type, headline},
     {max_payload_size, ?MAX_PAYLOAD_SIZE},
     {send_last_published_item, on_sub_and_presence},
     {deliver_notifications, true},
     {presence_based_delivery, true}].

features() ->
    ["create-nodes", %*
     "auto-create", %*
     "auto-subscribe", %*
     "delete-nodes", %*
     "delete-items", %*
     "filtered-notifications", %*
     "modify-affiliations",
     "outcast-affiliation",
     "persistent-items",
     "publish", %*
     "purge-nodes",
     "retract-items",
     "retrieve-affiliations",
     "retrieve-items", %*
     "retrieve-subscriptions",
     "subscribe" %*
    ].

create_node_permission(Host, ServerHost, _Node, _ParentNode, Owner, Access) ->
    LOwner = jlib:short_prepd_jid(Owner),
    {User, Server, Resource} = LOwner,
    Allowed = case LOwner of
	{undefined, Host, undefined} ->
	    true; % pubsub service always allowed
	_ ->
	    JID = exmpp_jid:make(User, Server, Resource),
	    case acl:match_rule(ServerHost, Access, JID) of
		allow ->
		    case Host of 
			{User, Server, _} -> true;
			_ -> false
		    end;
		E ->
		    ?DEBUG("Create not allowed : ~p~n", [E]),
		    false
	    end
    end,
    {result, Allowed}.

create_node(NodeId, Owner) ->
    case node_flat:create_node(NodeId, Owner) of
	{result, _} -> {result, []};
	Error -> Error
    end.

delete_node(Removed) ->
    case node_flat:delete_node(Removed) of
	{result, {_, _, Removed}} -> {result, {[], Removed}};
	Error -> Error
    end.

subscribe_node(NodeId, Sender, Subscriber, AccessModel,
	       SendLast, PresenceSubscription, RosterGroup, Options) ->
    node_flat:subscribe_node(
      NodeId, Sender, Subscriber, AccessModel, SendLast,
      PresenceSubscription, RosterGroup, Options).

unsubscribe_node(NodeId, Sender, Subscriber, SubId) ->
    case node_flat:unsubscribe_node(NodeId, Sender, Subscriber, SubId) of
	{error, Error} -> {error, Error};
	{result, _} -> {result, []}
    end.

publish_item(NodeId, Publisher, Model, MaxItems, ItemId, Payload) ->
    node_flat:publish_item(NodeId, Publisher, Model, MaxItems, ItemId, Payload).

remove_extra_items(NodeId, MaxItems, ItemIds) ->
    node_flat:remove_extra_items(NodeId, MaxItems, ItemIds).

delete_item(NodeId, Publisher, PublishModel, ItemId) ->
    node_flat:delete_item(NodeId, Publisher, PublishModel, ItemId).

purge_node(NodeId, Owner) ->
    node_flat:purge_node(NodeId, Owner).

get_entity_affiliations(_Host, Owner) ->
    {_, D, _} = jlib:short_prepd_jid(Owner),
    GenKey = jlib:short_prepd_bare_jid(Owner),
    States = mnesia:match_object(#pubsub_state{id = {GenKey, '_'}, _ = '_'}),
    NodeTree = case catch ets:lookup(gen_mod:get_module_proc(D, config), nodetree) of
	    [{nodetree, N}] -> N;
	    _ -> nodetree_tree
	end,
    Reply = lists:foldl(fun(#pubsub_state{id = {_, N}, affiliation = A}, Acc) ->
	case NodeTree:get_node(N) of
	    #pubsub_node{id = {{_, D, _}, _}} = Node -> [{Node, A}|Acc];
	    _ -> Acc
	end
    end, [], States),
    {result, Reply}.

get_node_affiliations(NodeId) ->
    node_flat:get_node_affiliations(NodeId).

get_affiliation(NodeId, Owner) ->
    node_flat:get_affiliation(NodeId, Owner).

set_affiliation(NodeId, Owner, Affiliation) ->
    node_flat:set_affiliation(NodeId, Owner, Affiliation).

get_entity_subscriptions(_Host, Owner) ->
    {U, D, _} = SubKey = jlib:short_prepd_jid(Owner),
    GenKey = jlib:short_prepd_bare_jid(Owner),
    States = case SubKey of
	GenKey -> mnesia:match_object(
	       #pubsub_state{id = {{U, D, '_'}, '_'}, _ = '_'});
	_ -> mnesia:match_object(
	       #pubsub_state{id = {GenKey, '_'}, _ = '_'})
	    ++ mnesia:match_object(
	       #pubsub_state{id = {SubKey, '_'}, _ = '_'})
    end,
    NodeTree = case catch ets:lookup(gen_mod:get_module_proc(D, config), nodetree) of
	    [{nodetree, N}] -> N;
	    _ -> nodetree_tree
	end,
    Reply = lists:foldl(fun(#pubsub_state{id = {J, N}, subscriptions = Ss}, Acc) ->
	case NodeTree:get_node(N) of
	    #pubsub_node{id = {{_, D, _}, _}} = Node ->
			lists:foldl(fun({subscribed, SubId}, Acc2) ->
					   [{Node, subscribed, SubId, J} | Acc2];
					({pending, _SubId}, Acc2) ->
					    [{Node, pending, J} | Acc2];
					(S, Acc2) ->
					    [{Node, S, J} | Acc2]
				    end, Acc, Ss);
	    _ -> Acc
	end
    end, [], States),
    {result, Reply}.

get_node_subscriptions(NodeId) ->
    %% note: get_node_subscriptions is used for broadcasting
    %% there should not have any subscriptions
    %% but that call returns also all subscription to none
    %% and this is required for broadcast to occurs
    %% DO NOT REMOVE
    node_flat:get_node_subscriptions(NodeId).

get_subscriptions(NodeId, Owner) ->
    node_flat:get_subscriptions(NodeId, Owner).

set_subscriptions(NodeId, Owner, Subscription, SubId) ->
    node_flat:set_subscriptions(NodeId, Owner, Subscription, SubId).

get_pending_nodes(Host, Owner) ->
    node_flat:get_pending_nodes(Host, Owner).

get_states(NodeId) ->
    node_flat:get_states(NodeId).

get_state(NodeId, JID) ->
    node_flat:get_state(NodeId, JID).

set_state(State) ->
    node_flat:set_state(State).

get_items(NodeId, From) ->
    node_flat:get_items(NodeId, From).

get_items(NodeId, JID, AccessModel, PresenceSubscription, RosterGroup, SubId) ->
    node_flat:get_items(NodeId, JID, AccessModel, PresenceSubscription, RosterGroup, SubId).

get_item(NodeId, ItemId) ->
    node_flat:get_item(NodeId, ItemId).

get_item(NodeId, ItemId, JID, AccessModel, PresenceSubscription, RosterGroup, SubId) ->
    node_flat:get_item(NodeId, ItemId, JID, AccessModel, PresenceSubscription, RosterGroup, SubId).

set_item(Item) ->
    node_flat:set_item(Item).

get_item_name(Host, Node, Id) ->
    node_flat:get_item_name(Host, Node, Id).

node_to_path(Node) ->
    node_flat:node_to_path(Node).

path_to_node(Path) ->
    node_flat:path_to_node(Path).


%%%
%%% Internal
%%%

%% @doc Check mod_caps is enabled, otherwise show warning.
%% The PEP plugin for mod_pubsub requires mod_caps to be enabled in the host.
%% Check that the mod_caps module is enabled in that Jabber Host
%% If not, show a warning message in the ejabberd log file.
complain_if_modcaps_disabled(ServerHost) ->
    Modules = ejabberd_config:get_local_option({modules, ServerHost}),
    ModCaps = [mod_caps_enabled || {mod_caps, _Opts} <- Modules],
    case ModCaps of
	[] ->
	    ?WARNING_MSG("The PEP plugin is enabled in mod_pubsub of host ~p. "
			 "This plugin requires mod_caps to be enabled, "
			 "but it isn't.", [ServerHost]);
	_ ->
	    ok
    end.
