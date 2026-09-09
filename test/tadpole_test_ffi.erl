%% Test-only recorder shared by the rest/ test modules: an ETS table that
%% stores the http requests a synthetic transport saw, marker strings for
%% ordering assertions, and a queue of canned responses. gleeunit runs
%% tests sequentially in one node, so one named table is enough; every
%% test starts with reset().
-module(tadpole_test_ffi).

-export([
    record_request/1,
    record_event/1,
    requests/0,
    events/0,
    reset/0,
    queue/1,
    next/0,
    get_env/1
]).

%% Reads one environment variable for the env-gated live test. Tokens
%% travel through the environment only: never argv, never files, never
%% this module's output.
get_env(Name) ->
    case os:getenv(unicode:characters_to_list(Name)) of
        false -> {error, nil};
        Value -> {ok, unicode:characters_to_binary(Value)}
    end.

table() ->
    Name = tadpole_test_recorder,
    case ets:whereis(Name) of
        undefined ->
            ets:new(Name, [named_table, public, set, {keypos, 1}]);
        _T ->
            ok
    end,
    Name.

record_request(Request) ->
    T = table(),
    [{requests, Rs}] = ets:lookup(T, requests),
    ets:insert(T, {requests, [Request | Rs]}),
    nil.

record_event(Event) ->
    T = table(),
    [{events, Es}] = ets:lookup(T, events),
    ets:insert(T, {events, [Event | Es]}),
    nil.

requests() ->
    T = table(),
    [{requests, Rs}] = ets:lookup(T, requests),
    lists:reverse(Rs).

events() ->
    T = table(),
    [{events, Es}] = ets:lookup(T, events),
    lists:reverse(Es).

reset() ->
    T = table(),
    ets:insert(T, [{requests, []}, {events, []}, {queue, []}]),
    nil.

queue(Response) ->
    T = table(),
    [{queue, Q}] = ets:lookup(T, queue),
    ets:insert(T, {queue, Q ++ [Response]}),
    nil.

next() ->
    T = table(),
    case ets:lookup(T, queue) of
        [{queue, [Next | Rest]}] ->
            ets:insert(T, {queue, Rest}),
            {ok, Next};
        _ ->
            {error, nil}
    end.
