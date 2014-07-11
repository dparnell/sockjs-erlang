#!/usr/bin/env escript
%%! -smp disable +A1 +K true -pa ebin -env ERL_LIBS deps -input
-module(cowboy_echo).
-mode(compile).

-export([main/1]).

%% Cowboy callbacks
-export([init/3, handle/2, terminate/3]).


main(_) ->
    Port = 8081,
    ok = application:start(xmerl),
    ok = application:start(sockjs),
    ok = application:start(ranch),
    ok = application:start(crypto),
    ok = application:start(cowlib),
    ok = application:start(cowboy),

    SockjsState = sockjs_handler:init_state(
                    <<"/echo">>, fun authen/3, fun service_echo/3, state, []),

    VhostRoutes = [{<<"/echo/[...]">>, sockjs_cowboy_handler, SockjsState},
                   {'_', ?MODULE, []}],
    Routes = [{'_',  VhostRoutes}], % any vhost
    Dispatch = cowboy_router:compile(Routes),

    io:format(" [*] Running at http://localhost:~p~n", [Port]),
    cowboy:start_http(cowboy_echo_http_listener, 100,
                      [{port, Port}],
                      [{env, [{dispatch, Dispatch}]}]),
    receive
        _ -> ok
    end.

%% --------------------------------------------------------------------------

init({_Any, http}, Req, []) ->
    {ok, Req, []}.

handle(Req, State) ->
    {ok, Data} = file:read_file("./examples/echo_authen_callback.html"),
    {ok, Req1} = cowboy_req:reply(200, [{<<"Content-Type">>, "text/html"}],
                                       Data, Req),
    {ok, Req1, State}.

terminate(_Reason, _Req, _State) ->
    ok.

%% --------------------------------------------------------------------------

authen(Conn, init, State) ->
    {ok, TRef} = timer:apply_after(5000, sockjs, close, [Conn]),
    {ok, [TRef | State]};
authen(Conn, {recv, Data}, [TRef | State] = State1) ->
    case Data of
        <<"auth">> ->
            sockjs:send(<<"Authenticate successfully!">>, Conn),
            timer:cancel(TRef),
            {success, [{user_id, element(3, erlang:now())} | State]};
        _Else ->
            {ok, State1}
    end;
authen(_Conn, closed, State) ->
    {ok, State}.

service_echo(_Conn, init, State) ->
    {ok, State};
service_echo(Conn, {recv, Data}, State) ->
    {user_id, UserId} = lists:keyfind(user_id, 1, State),
    sockjs:send([Data, " from ", erlang:integer_to_binary(UserId)], Conn);
service_echo(_Conn, {info, _Info}, State) ->
    {ok, State};
service_echo(_Conn, closed, State) ->
    {ok, State}.