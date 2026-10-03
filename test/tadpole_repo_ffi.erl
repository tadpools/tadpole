%% Test-only reader for repo files that are not fixtures. Same relative-path
%% trick as tadpole_fixture_ffi: the compiler sets the CWD to the package
%% root when running `gleam test`, so these paths work locally and in CI.
-module(tadpole_repo_ffi).

-export([read/1]).

read(Name) ->
    case file:read_file(Name) of
        {ok, Binary} -> {ok, unicode:characters_to_binary(Binary)};
        {error, _} -> {error, nil}
    end.