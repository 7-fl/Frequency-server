I wrote an adapter pattern for the ```allocate()```/```deallocate()``` methods so that the client 
can communicate with the adapter by sending and receiving messages--rather than 
calling ```allocate()``` and ```deallocate()``` directly.  That way the client can sit in a
receive waiting for messages from the adapter process, and if the server fails,
which will also take down the (linked) adapter process, the client will end up 
waiting indefinitely in a receive--unaffected by the server failing.  As far as 
the client knows, the server is busy.

```
Process diagram:

 ()   process
 <->  message sending between processes
 -->  function call

(client) <-> (request_adapter --> allocate/deallocate)  <->  (server)
                                                        link   trap
                                                        
```                         
To shutdown the whole system,
I called ```exit(Client, shutdown)``` on each client, where the atom
**shutdown** is just a random atom different from the atom **normal**.
That causes each
client to immediately end its allocate/deallocate message sending to the adapter
process.  Then I called ```exit(Server, kill)``` on the server, which also kills
the linked adapter processes.  Calling ```stop()``` on the 
sever is problematic because it does not cause the adapter processes
that are linked to the server to shutdown because the sever exits normally 
in response to ```stop()```.  And calling ```exit(Server, shutdown)``` doesn't kill
the server because the server is trapping exits.

**Problems**: It seems to me that there is a race condition in my code.
If I happen to kill a client immediately after it sends a message
to the adapter, and then I kill the server before the corresponding
message from
the adapter is sent to the server, the adapter might live long enough before it
it is killed  (by virtue of being linked to the server) to do:
```erlang
    f3 ! Msg
```
which would cause a badarg error.  I tested out that theory by 
putting a timeout at the top of the adpater, and it does cause
a badarg error, but all the processes still shutdown, so
I'm calling it good.

```erlang
In the shell:

1> c(f3).
{ok,f3}

2> f3:test2().
client1 (<0.44.0>) given frequency: 10
client2 (<0.45.0>) given frequency: 11
client2 (<0.45.0>) deallocated frequency: 11
client2 (<0.45.0>) given frequency: 11
client1 (<0.44.0>) deallocated frequency: 10
client1 (<0.44.0>) given frequency: 10
client2 (<0.45.0>) deallocated frequency: 11
client2 (<0.45.0>) given frequency: 11
client2 (<0.45.0>) deallocated frequency: 11
client2 (<0.45.0>) given frequency: 11
client1 (<0.44.0>) deallocated frequency: 10
client1 (<0.44.0>) given frequency: 10
client2 (<0.45.0>) deallocated frequency: 11
client2 (<0.45.0>) given frequency: 11
client2 (<0.45.0>) deallocated frequency: 11
client2 (<0.45.0>) given frequency: 11
---Shutting down client: <0.44.0>
---Shutting down client: <0.45.0>
---Shutting down server: <0.43.0>
system_shutdown

3> i().
Pid                   Initial Call                          Heap     Reds Msgs
Registered            Current Function                     Stack              
<0.0.0>               otp_ring0:start/2                     1598     3216    0
init                  init:loop/1                              2              
<0.3.0>               erlang:apply/2                        6772   652123    0
erl_prim_loader       erl_prim_loader:loop/3                   6              
<0.6.0>               gen_event:init_it/6                    376      223    0
error_logger          gen_event:fetch_msg/5                    8              
<0.7.0>               erlang:apply/2                        1598      470    0
application_controlle gen_server:loop/6                        7              
<0.9.0>               application_master:init/4              376       44    0
                      application_master:main_loop/2           6              
<0.10.0>              application_master:start_it/4          233       69    0
                      application_master:loop_it/4             5              
<0.11.0>              supervisor:kernel/1                   2586    45786    0
kernel_sup            gen_server:loop/6                        9              
<0.12.0>              rpc:init/1                             233       35    0
rex                   gen_server:loop/6                        9              
<0.13.0>              global:init/1                          233       52    0
global_name_server    gen_server:loop/6                        9              
<0.14.0>              erlang:apply/2                         233       19    0
                      global:loop_the_locker/1                 5              
<0.15.0>              erlang:apply/2                         233        3    0
                      global:loop_the_registrar/0              2              
<0.16.0>              inet_db:init/1                         233      251    0
inet_db               gen_server:loop/6                        9              
<0.17.0>              global_group:init/1                    233       59    0
global_group          gen_server:loop/6                        9              
<0.18.0>              file_server:init/1                     610      675    0
file_server_2         gen_server:loop/6                        9              
<0.19.0>              erlang:apply/2                        1598   120968    0
code_server           code_server:loop/1                       3              
<0.20.0>              supervisor_bridge:standard_error/      233       41    0
standard_error_sup    gen_server:loop/6                        9              
<0.21.0>              erlang:apply/2                         233        9    0
standard_error        standard_error:server_loop/1             2              
<0.22.0>              supervisor_bridge:user_sup/1           233       60    0
                      gen_server:loop/6                        9              
<0.23.0>              user_drv:server/2                     2586     3240    0
user_drv              user_drv:server_loop/5                   8              
<0.24.0>              group:server/3                         233      192    0
user                  group:server_loop/3                      4              
<0.25.0>              group:server/3                        1598    15067    0
                      group:server_loop/3                      4              
<0.26.0>              erlang:apply/2                       17731     3947    0
                      shell:shell_rep/4                       17              
<0.27.0>              kernel_config:init/1                   233      286    0
                      gen_server:loop/6                        9              
<0.28.0>              supervisor:kernel/1                    233       58    0
kernel_safe_sup       gen_server:loop/6                        9              
<0.32.0>              erlang:apply/2                         376    19705    0
                      c:pinfo/1                               50              
Total                                                      40834   866598    0
                                                             219              
ok
4> 
```


