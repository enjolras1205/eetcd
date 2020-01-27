-module(eetcd_kv).
-include("eetcd.hrl").

-export([put/1, put/3]).
-export([get/1, get/2]).
-export([delete/1, delete/2]).
-export([compact/1, compact/2]).
-export([txn/4]).

-export([
    with_key/2, with_value/2, with_prefix/1,
    with_lease/2, with_ignore_value/1, with_ignore_lease/1,
    with_from_key/1, with_range_end/2, with_limit/2,
    with_rev/2, with_sort/3, with_serializable/1,
    with_keys_only/1, with_count_only/1,
    with_min_mod_rev/2, with_max_mod_rev/2, with_min_create_rev/2,
    with_max_create_rev/2, with_first_create/1, with_last_create/1,
    with_first_rev/1, with_last_rev/1, with_first_key/1, with_last_key/1,
    with_top/3, with_prev_kv/1
]).

%%% @doc Sets data for the request's `key'.
-spec with_key(context(), key()) -> context().
with_key(Context, Key) ->
    maps:put(key, Key, Context).

%% @doc Sets data for the request's `value'.
-spec with_value(context(), key()) -> context().
with_value(Context, Key) ->
    maps:put(value, Key, Context).

%% @doc Enables `get', `delete' requests to operate
%% on the keys with matching prefix. For example, `get("foo", with_prefix())'
%% can return 'foo1', 'foo2', and so on.
-spec with_prefix(context()) -> context().
with_prefix(Context) ->
    with_range_end(Context, "\0").

%%  @doc Specifies the range of `get', `delete' requests
%% to be equal or greater than the key in the argument.
-spec with_from_key(context()) -> context().
with_from_key(Context) ->
    with_range_end(Context, "\x00").

%% @doc Sets the byte slice for the request's `range_end'.
-spec with_range_end(context(), iodata()) -> context().
with_range_end(Context, End) ->
    maps:put(range_end, End, Context).

%% @doc Limit the number of results to return from `get' request.
%% If with_limit is given a 0 limit, it is treated as no limit.
-spec with_limit(context(), iodata()) -> context().
with_limit(Context, End) ->
    maps:put(limit, End, Context).

%% @doc Specifies the store revision for `get' request.
-spec with_rev(context(), pos_integer()) -> context().
with_rev(Context, Rev) ->
    maps:put(revision, Rev, Context).

%% @doc Specifies the ordering in `get' request. It requires
%% `with_range' and/or `with_prefix' to be specified too.
%% `target' specifies the target to sort by: 'KEY', 'VERSION', 'VALUE', 'CREATE', 'MOD'.
%% `order' can be either 'NONE', 'ASCEND', 'DESCEND'.
-spec with_sort(context(),
    'KEY' | 'VERSION' | 'VALUE' | 'CREATE' |'MOD',
    'NONE' | 'ASCEND' | 'DESCEND') -> context().
with_sort(Context, Target, Order) ->
    Targets = router_pb:find_enum_def('Etcd.RangeRequest.SortTarget'),
    Orders = router_pb:find_enum_def('Etcd.RangeRequest.SortOrder'),
    (not lists:keymember(Target, 1, Targets)) andalso throw({sort_target, Target}),
    (not lists:keymember(Order, 1, Orders)) andalso throw({sort_order, Order}),
    R1 = maps:put(sort_order, Order, Context),
    maps:put(sort_target, Target, R1).

%% @doc Make `get' request serializable. By default,
%% it's linearizable. Serializable requests are better for lower latency
%% requirement.
-spec with_serializable(context()) -> context().
with_serializable(Context) ->
    maps:put(serializable, true, Context).

%% @doc Make the `get' request return only the keys and the corresponding
%% values will be omitted.
-spec with_keys_only(context()) -> context().
with_keys_only(Context) ->
    maps:put(keys_only, true, Context).

%% @doc Make the `get' request return only the count of keys.
-spec with_count_only(context()) -> context().
with_count_only(Context) ->
    maps:put(count_only, true, Context).

%% @doc Filter out keys for `get' with modification revisions less than the given revision.
-spec with_min_mod_rev(context(), pos_integer()) -> context().
with_min_mod_rev(Context, Rev) ->
    maps:put(min_mod_revision, Rev, Context).

%% @doc Filter out keys for `get' with modification revisions greater than the given revision.
-spec with_max_mod_rev(context(), pos_integer()) -> context().
with_max_mod_rev(Context, Rev) ->
    maps:put(max_mod_revision, Rev, Context).

%% @doc Filter out keys for `get' with creation revisions less than the given revision.
-spec with_min_create_rev(context(), pos_integer()) -> context().
with_min_create_rev(Context, Rev) ->
    maps:put(min_create_revision, Rev, Context).

%% @doc Filter out keys for `get' with creation revisions greater than the given revision.
-spec with_max_create_rev(context(), pos_integer()) -> context().
with_max_create_rev(Context, Rev) ->
    maps:put(max_create_revision, Rev, Context).

%% @doc Get the key with the oldest creation revision in the request range.
-spec with_first_create(context()) -> context().
with_first_create(Context) ->
    with_top(Context, 'CREATE', 'ASCEND').

%% @doc Get the lexically last key in the request range.
-spec with_last_create(context()) -> context().
with_last_create(Context) ->
    with_top(Context, 'CREATE', 'DESCEND').

%% @doc Get the key with the oldest modification revision in the request range.
-spec with_first_rev(context()) -> context().
with_first_rev(Context) ->
    with_top(Context, 'MOD', 'ASCEND').

%% @doc Get the key with the latest modification revision in the request range.
-spec with_last_rev(context()) -> context().
with_last_rev(Context) ->
    with_top(Context, 'MOD', 'DESCEND').

%% @doc Get the lexically first key in the request range.
-spec with_first_key(context()) -> context().
with_first_key(Context) ->
    with_top(Context, 'KEY', 'ASCEND').

%% @doc Get the lexically last key in the request range.
-spec with_last_key(context()) -> context().
with_last_key(Context) ->
    with_top(Context, 'KEY', 'DESCEND').

%% @doc Get the first key over the get's prefix given a sort order
-spec with_top(context(),
    'KEY' | 'VERSION' | 'VALUE' | 'CREATE' |'MOD',
    'NONE' | 'ASCEND' | 'DESCEND') -> context().
with_top(Context, SortTarget, SortOrder) ->
    C1 = with_sort(Context, SortTarget, SortOrder),
    with_limit(C1, 1).

%% @doc Get the previous key-value pair before the event happens.
%% If the previous KV is already compacted, nothing will be returned.
-spec with_prev_kv(context()) -> context().
with_prev_kv(Context) ->
    maps:put(prev_kv, true, Context).

%% @doc Attache a lease ID to a key in `put' request.
-spec with_lease(context(), integer()) -> context().
with_lease(Context, Id) when is_integer(Id) ->
    maps:put(lease, Id, Context).

%% @doc Update the key using its current value.
%% This option can not be combined with non-empty values.
%% Returns an error if the key does not exist.
-spec with_ignore_value(context()) -> context().
with_ignore_value(Context) ->
    maps:put(ignore_value, true, Context).

%% @doc Update the key using its current lease.
%% This option can not be combined with `with_lease/2'.
%% Returns an error if the key does not exist.
-spec with_ignore_lease(context()) -> context().
with_ignore_lease(Context) ->
    maps:put(ignore_lease, true, Context).

%%% @doc Put puts a key-value pair into etcd.
%%% <dl>
%%% <dt> 1. base </dt>
%%% <dd> `eetcd_kv:put(ConnName, Key, Value).' </dd>
%%% <dt> 2. with lease id </dt>
%%% <dd> `eetcd_kv:put(Key, Value, eetcd:with_lease(eetcd:new(ConnName), LeaseID)).' </dd>
%%% <dt> 3. elixir </dt>
%%% <dd>
%%% ```
%%% :eetcd.new(connName)
%%% |> :eetcd.with_key(key)
%%% |> :eetcd.with_value(value)
%%% |> :eetcd.with_lease(leaseId)
%%% |> :eetcd.with_ignore_value()
%%% |> :eetcd.with_ignore_lease()
%%% |> :eetcd.with_timeout(6000)
%%% |> :eetcd_kv.put()
%%% '''
%%% </dd> </dl>
%%% {@link eetcd:with_key/2}, {@link eetcd:with_value/2}, {@link eetcd:with_lease/2},
%%% {@link eetcd:with_ignore_value/2}, {@link eetcd:with_ignore_lease/2}, {@link eetcd:with_timeout/2}
%%% @end
-spec put(context()) ->
    {ok, router_pb:'Etcd.PutResponse'()}|{error, eetcd_error()}.
put(Context) -> eetcd_kv_gen:put(Context).

%%% @doc Put puts a key-value pair into etcd with options {@link put/1}
-spec put(name(), key(), value()) ->
    {ok, router_pb:'Etcd.PutResponse'()}|{error, eetcd_error()}.
put(Context, Key, Value) when is_map(Context) ->
    Context0 = eetcd:with_key(Context, Key),
    Context1 = eetcd:with_value(Context0, Value),
    eetcd_kv_gen:put(Context1);
put(ConnName, Key, Value) -> put(eetcd:new(ConnName), Key, Value).

%%% @doc Get retrieves keys.
%%% By default, Get will return the value for Key, if any.
%%% When passed {@link eetcd:with_range_end/2}, Get will return the keys in the range `[Key, End)'.
%%% When passed {@link eetcd:with_from_key/1}, Get returns keys greater than or equal to key.
%%% When passed {@link eetcd:with_revision/2} with Rev > 0, Get retrieves keys at the given revision;
%%% if the required revision is compacted, the request will fail with ErrCompacted.
%%% When passed {@link eetcd:with_limit/1}, the number of returned keys is bounded by Limit.
%%% When passed {@link eetcd:with_sort/3}, the keys will be sorted.
%%% <dl>
%%% <dt> 1.base </dt>
%%% <dd> `eetcd_kv:get(ConnName,Key).'</dd>
%%% <dt> 2.with range end </dt>
%%% <dd> `eetcd_kv:get(eetcd:with_range_end(eetcd:with_key(eetcd:new(ConnName),Key),End)).' </dd>
%%% <dt> 3.Elixir </dt>
%%% <dd>
%%% ```
%%% :eetcd.new(connName)
%%% |> :eetcd.with_key(key)
%%% |> :eetcd.with_range_end(rangeEnd)
%%% |> :eetcd.with_limit(limit)
%%% |> :eetcd.with_revision(rev)
%%% |> :eetcd.with_sort(:'KEY', :'ASCEND')  %% 'NONE' | 'ASCEND' | 'DESCEND' enum Etcd.RangeRequest.SortOrder
%%% |> :eetcd.with_serializable()
%%% |> :eetcd.with_keys_only()
%%% |> :eetcd.with_count_only()
%%% |> :eetcd.with_min_mod_revision(minModRev)
%%% |> :eetcd.with_max_mod_revision(maxModRev)
%%% |> :eetcd.with_min_create_revision(minCreateRev)
%%% |> :eetcd.with_max_create_revision(maxCreateRev)
%%% |> :eetcd_kv:get()
%%% '''
%%% </dd>
%%% </dl>
%%% {@link eetcd:with_key/2} {@link eetcd:with_range_end/2} {@link eetcd:with_limit/2}
%%% {@link eetcd:with_revision/2} {@link eetcd:with_sort/3}
%%% {@link eetcd:with_serializable/1} {@link eetcd:with_keys_only/1}
%%% {@link eetcd:with_count_only/1} {@link eetcd:with_min_mod_revision/2}
%%% {@link eetcd:with_max_mod_revision/2} {@link eetcd:with_min_create_revision/2} {@link eetcd:with_max_create_revision/2}
%%% @end
-spec get(context()) ->
    {ok, router_pb:'Etcd.RangeResponse'()}|{error, eetcd_error()}.
get(Context) when is_map(Context) -> eetcd_kv_gen:range(Context).
%%% @doc Get retrieves keys with options.
-spec get(context()|name(), key()) ->
    {ok, router_pb:'Etcd.RangeResponse'()}|{error, eetcd_error()}.
get(Context, Key) when is_map(Context) -> eetcd_kv_gen:range(eetcd:with_key(Context, Key));
get(ConnName, Key) -> eetcd_kv_gen:range(eetcd:with_key(eetcd:new(ConnName), Key)).

%%% @doc Delete deletes a key, or optionally using eetcd:with_range(End), [Key, End).
%%% <dl>
%%% <dt> 1.base </dt>
%%% <dd> `eetcd_kv:delete(ConnName,Key).' </dd>
%%% <dt> 2.with range end </dt>
%%% <dd> `eetcd_kv:delete(eetcd:with_range_end(eetcd:with_key(eetcd:new(ConnName),Key), End)).'</dd>
%%% <dt> 3.elixir </dt>
%%% <dd>
%%% ```
%%% :eetcd.new(ConnName)
%%% |> :eetcd.with_key(key)
%%% |> :eetcd.with_range_end(rangeEnd)
%%% |> :eetcd.with_prev_kv()
%%% |> :eetcd_kv.delete()
%%% '''
%%% </dd> </dl>
%%% {@link eetcd:with_key/2} {@link eetcd:with_range_end/2} {@link eetcd:with_prev_kv/1}
%%% @end
-spec delete(context()) ->
    {ok, router_pb:'Etcd.DeleteRangeResponse'()}|{error, eetcd_error()}.
delete(Context) when is_map(Context) -> eetcd_kv_gen:delete_range(Context).
%%% @doc Delete deletes a key with options
-spec delete(name()|context(), key()) ->
    {ok, router_pb:'Etcd.DeleteRangeResponse'()}|{error, eetcd_error()}.
delete(Context, Key) when is_map(Context) -> eetcd_kv_gen:delete_range(eetcd:with_key(Context, Key));
delete(ConnName, Key) -> eetcd_kv_gen:delete_range(eetcd:with_key(eetcd:new(ConnName), Key)).

%% @doc Compact compacts etcd KV history before the given revision.
%%% <dl>
%%% <dt> 1.base </dt>
%%% <dd> `eetcd_kv:compact(ConnName,Revision).'</dd>
%%% <dt> 2.with physical</dt>
%%% <dd> `eetcd_kv:compact(eetcd:with_physical(eetcd:with_revision(eetcd:new(ConnName), Revision))).'</dd>
%%% <dt> 3.Elixir </dt>
%%% <dd>
%%% ```
%%% :eetcd.new(ConnName)
%%% |> :eetcd.with_revision(revision)
%%% |> :eetcd.with_physical()
%%% |> :eetcd_kv.compact()
%%% '''
%%% </dd> </dl>
%%% {@link eetcd:with_revision/2} {@link eetcd:with_physical/1}
%%% @end
-spec compact(context()) ->
    {ok, router_pb:'Etcd.CompactionResponse'()}|{error, eetcd_error()}.
compact(Context) when is_map(Context) -> eetcd_kv_gen:compact(Context).
%% @doc Compact compacts etcd KV history before the given revision with options
-spec compact(name()|context(), integer()) ->
    {ok, router_pb:'Etcd.CompactionResponse'()}|{error, eetcd_error()}.
compact(Context, Revision) when is_map(Context) -> eetcd_kv_gen:compact(eetcd:with_rev(Context, Revision));
compact(ConnName, Revision) -> eetcd_kv_gen:compact(eetcd:with_rev(eetcd:new(ConnName), Revision)).

%%% @doc Txn creates a transaction.
%% <dd>If takes a list of comparison. If all comparisons passed in succeed,</dd>
%% <dd>the operations passed into Then() will be executed.</dd>
%% <dd>Or the operations passed into Else() will be executed.</dd>
%% <dd>Then takes a list of operations. The Ops list will be executed, if the comparisons passed in If() succeed.</dd>
%% <dd> Else takes a list of operations. The Ops list will be executed, if the comparisons passed in If() fail.</dd>
%% Cmp = eetcd:with_key(#{}, Key),
%% If = eetcd_compare:value(Cmp, ">", Value),
%% Then = eetcd_op:put(eetcd:with_value(eetcd:with_key(eetcd:new(), Key), "NewValue")),
%% Else = eetcd_op:delete_range(eetcd:with_key(eetcd:new(), Key))
%%% @end
-spec txn(name()|context(), [router_pb:'Etcd.Compare'()], [router_pb:'Etcd.RequestOp'()], [router_pb:'Etcd.RequestOp'()]) ->
    {ok, router_pb:'Etcd.TxnResponse'()}|{error, eetcd_error()}.
txn(Context, If, Then, Else) when is_map(Context) ->
    Txn = maps:merge(#{compare => If, success => Then, failure => Else}, Context),
    eetcd_kv_gen:txn(Txn);
txn(ConnName, If, Then, Else) ->
    txn(eetcd:new(ConnName), If, Then, Else).
