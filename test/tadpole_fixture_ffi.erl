%% Test-only fixture loader for the contract tests: reads a payload file
%% from test/fixtures relative to the repo root. The compiler sets the
%% CWD to the package root when running `gleam test`, so a relative path
%% works locally and in CI alike.
-module(tadpole_fixture_ffi).

-export([read/1]).

read(Name) ->
    Path = filename:join(["test", "fixtures", Name]),
    case file:read_file(Path) of
        {ok, Binary} -> {ok, unicode:characters_to_binary(Binary)};
        {error, _} -> {error, nil}
    end.
