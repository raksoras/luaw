#10. Async HTTP Client

Luaw comes equipped with curl like async HTTP client. It is fully async, in that both DNS lookup for the hostname as well as actual connect/read/write on the socket are done in a non blocking fashion. Due to this you can use this client safely in your Luaw webapp, from your request thread to make HTTP requests to other backend servers. Luaw will transparently suspend your running request thread (Lua coroutine) when the HTTP client is waiting on DNS lookup, connect, read or write.

The Luaw HTTP client is modeled by two objects: clientHttpRequest and clientHttpResponse. Here is a small example of Luaw's HTTP client's usage:

```lua
-- set up HTTP request
local clientReq = Luaw.newClientHttpRequest()
clientReq.hostName = "www.google.com"
-- OR alternatively,
clientReq.hostIP = "74.125.25.106"
clientReq.method = 'GET'
clientReq.url = "/"

clientReq.headers = { Host = "www.google.com" }
-- OR alternatively
clientReq:addHeader("Host", "www.google.com")

-- execute the HTTP request and read the response back.
local clientResp = clientReq:execute()

-- Get the respone headers and body from the client response object returned
local respBody = clientResp.body
local respHeaders = clientResp.headers
```

In fact, Luaw's built in HTTP client allows even more fine grained control over various stages of HTTP request execution and parsing of the HTTP response received from the server, similar to what we saw in the chapter "Advanced Topic I - Using Response Object" which was about server's HTTP response. We learn will how to use some of these methods in the last chapter where we put together all the things we have learned so far to develop a streaming request/response handler for a high performance proxy web server.



