%% Based on code from 
%%   Erlang Programming
%%   Francecso Cesarini and Simon Thompson
%%   O'Reilly, 2008
%%   http://oreilly.com/catalog/9780596518189/
%%   http://www.erlangprogramming.org/
%%   (c) Francesco Cesarini and Simon Thompson

-module(f3).
-export([start/0,allocate/0,deallocate/1,stop/0]).
-export([init/0]).
-export([client/3, client_init/2, request_adapter/0]).
-export([test1/0, test_process1/0, test2/0, test_process2/0]).
-include_lib("eunit/include/eunit.hrl").

%I wrote an adapter pattern for the allocate/deallocate methods so that the client 
%can communicate with the adapter by sending and receiving messages--rather than 
%calling allocate() and deallocate() directly.  That way the client can sit in a
%receive waiting for messages from the adapter process, and if the server fails,
%which will also take down the (linked) adapter process, the client will end up  
%waiting indefinitely in a receive--unaffected by the server failing.  As far as 
%the client knows, the server is busy.

% Process diagram:
%  ()   process
%  <->  message sending between processes
%  -->  function call
%
% (client) <-> (request_adapter --> allocate/deallocate)  <->  (server)
%                                                         link   trap
%
% To shutdown the whole system,
% I called exit(Client, shutdown) on each client, where the atom
% shutdown is just a random atom different from the atom normal.
% That causes each
% client to immediately end its allocate/deallocate looping. 
% Then I called exit(Server, kill) on the server. Calling stop() on the 
% sever is problematic because it does not cause the adapter process that
% is linked to the server to shutdown because the sever exits normally 
% in response to stop().
%
% Problems: It seems to me that there is a race condition in my code.
% If I happen to kill a client immediately after it sends a message
% to the adapter, and then I kill the server before the corresponding
% message from
% the adapter is sent, the adapter might live long enough before it
% it is killed  (by virtue of being linked to the server) to do:
%     f3 ! Msg
% which would cause a badarg error.  I tested out that theory by 
% putting a timeout at the top of the adpater, and it does cause
% a badarg exception, but all the processes still shutdown, so
% I'm calling it good.

%--------------

% I used test1() so that I could use the observer to kill 
% the server and make sure the clients were unaffected.
test1() ->
    spawn(f3, test_process1, []).  %Enables me to execute observer:start() in the shell

test_process1() ->
    start(),
    _Client1 = spawn(f3, client_init, [1, 5000]),
    _Client2 = spawn(f3, client_init, [2, 2500]).
  
% I used test2() to work on shutting down the whole system with code.
test2() ->
    start(),
    Client1 = spawn(f3, client_init, [1, 5000]),
    Client2 = spawn(f3, client_init, [2, 2500]),
    timer:sleep(15000),  %Let the clients send requests to the server for awhile,
    shutdown_system([Client1, Client2], f3).

%--------------

client_init(Id, Sleep) ->
    RequestAdapter = spawn(f3, request_adapter, []),
    client(Id, Sleep, RequestAdapter).

%--------------

request_adapter() ->
    %timer:sleep(1000),  %For testing race condition.
    receive
        {allocate, Sender} ->  %Client sends this message to the adapter.
            Response = allocate(),  %The adapter calls allocate()/deallocate() and gets the return value.
            Sender ! {self(), Response}, %The adapter sends the server's response back to the client.
            request_adapter();
        {deallocate, Freq, Sender} ->
            Response = deallocate(Freq),
            Sender ! Response,
            request_adapter()
    end.
 

%------------

client(Id, Sleep, RequestAdapter) -> 
    RequestAdapter ! {allocate, self()},
    receive
        {RequestAdapter, {ok, Freq}} -> 
            io:format("client~w (~w) given frequency: ~w~n", [Id, self(), Freq] ),
            timer:sleep(Sleep),
            do_deallocation(Freq, RequestAdapter, Id),
            client(Id, Sleep, RequestAdapter);
        {RequestAdapter, {error, no_frequency}} ->
            io:format("client~w (~w): **no frequencies available**~n", [Id, self()]),
            client(Id, Sleep, RequestAdapter)
    end.

%------------

do_deallocation(Freq, RequestAdapter, Id) ->
    RequestAdapter ! {deallocate, Freq, self()},
    receive
        ok ->
            io:format("client~w (~w) deallocated frequency: ~w~n", [Id, self(), Freq]);
        _Other ->
            io:format("client~w (~w) couldn't deallocate frequency: ~w~n", [Id, self(), Freq])
    end.                                        
 
%--------------

shutdown_system(Clients, Server) ->
    shutdown_clients(Clients),
    shutdown_server(whereis(Server) ),
    system_shutdown.
    
shutdown_clients([]) ->
    all_clients_shutdown;
shutdown_clients([Client|Clients]) ->
    io:format("---Shutting down client: ~w~n", [Client]),
    exit(Client, shutdown),
    shutdown_clients(Clients).

shutdown_server(undefined) ->
    server_already_shutdown;
shutdown_server(Pid) ->
    io:format("---Shutting down server: ~w~n", [Pid]),
    exit(Pid, kill).

%------------------------------------------------------
%--- No changes to the server code we were given   ----
%------------------------------------------------------

%These are the start functions used to create and
%initialize the server.

start() ->
    register(f3,
	     spawn(f3, init, [])).

init() ->
  process_flag(trap_exit, true),    %%% ADDED
  Frequencies = {get_frequencies(), []},
  loop(Frequencies).

% Hard Coded
get_frequencies() -> [10,11,12,13,14,15].

%% The Main Loop

loop(Frequencies) ->
  receive
    {request, Pid, allocate} ->
      {NewFrequencies, Reply} = allocate(Frequencies, Pid),
      Pid ! {reply, Reply},
      loop(NewFrequencies);
    {request, Pid , {deallocate, Freq}} ->
      NewFrequencies = deallocate(Frequencies, Freq),
      Pid ! {reply, ok},
      loop(NewFrequencies);
    {request, Pid, stop} ->
      Pid ! {reply, stopped};
    {'EXIT', Pid, _Reason} ->                   %%% CLAUSE ADDED
      NewFrequencies = exited(Frequencies, Pid), 
      loop(NewFrequencies)
  end.

%% Functional interface

allocate() -> 
    f3 ! {request, self(), allocate},
    receive 
            {reply, Reply} -> Reply
    end.

deallocate(Freq) -> 
    f3 ! {request, self(), {deallocate, Freq}},
    receive 
	    {reply, Reply} -> Reply
    end.

stop() -> 
    f3 ! {request, self(), stop},
    receive 
	    {reply, Reply} -> Reply
    end.

%% The Internal Help Functions used to allocate and
%% deallocate frequencies.

allocate({[], Allocated}, _Pid) ->
  {{[], Allocated}, {error, no_frequency}};
allocate({[Freq|Free], Allocated}, Pid) ->
  link(Pid),                                               %%% ADDED
  {{Free, [{Freq, Pid}|Allocated]}, {ok, Freq}}.

deallocate({Free, Allocated}, Freq) ->
  {value,{Freq,Pid}} = lists:keysearch(Freq,1,Allocated),  %%% ADDED
  unlink(Pid),                                             %%% ADDED
  NewAllocated=lists:keydelete(Freq, 1, Allocated),
  {[Freq|Free],  NewAllocated}.

exited({Free, Allocated}, Pid) ->                %%% FUNCTION ADDED
    case lists:keysearch(Pid,2,Allocated) of
      {value,{Freq,Pid}} ->
        NewAllocated = lists:keydelete(Freq,1,Allocated),
        {[Freq|Free],NewAllocated}; 
      false ->
        {Free,Allocated} 
    end.

