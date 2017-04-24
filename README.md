I wrote an adapter pattern for the allocate/deallocate methods so that the client 
can communicate with the adapter by sending and receiving messages--rather than 
calling allocate() and deallocate() directly.  That way the client can sit in a
receive waiting for messages from the adapter process, and if the server fails,
which will also take down the (linked) adapter process, the client will end up 
waiting indefinitely in a receive--unaffected by the server failing.  As far as 
the client knows, the server is busy.

```erlang
Process diagram:
 ()   process
 <->  message sending between processes
 -->  function call

(client) <-> (request_adapter --> allocate/deallocate)  <->  (server)
                                                        link   trap
                                                        
```                         
To shutdown the whole system, 
I called ```exit(Client, shutdown)``` on each client, where the atom shutdown is 
just a random atom different from the atom normal. That causes each
client to immediately end its allocate/deallocate looping. 
Then I called ```exit(Server, kill)``` on the server. Calling ```stop()``` on the 
sever is problematic because it does not cause the adapter process that
is linked to the server to shutdown because the sever exits normally 
in response to stop().

**Problems**: It seems to me that there is a race condition in my code.
If I happen to kill a client immediately after it sends a message
to the adapter, and then I kill the server before the corresponding
message from
the adapter is sent, the adapter might live long enough before it
it is killed  (by virtue of being linked to the server) to do:
```erlang
    f3 ! Msg
```
which would cause a badarg error.  I tested out that theory by 
putting a timeout at the top of the adpater, and it does cause
a badarg exception, but all the processes still shutdown, so
I'm calling it good.

