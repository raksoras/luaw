#9. Response Object

So far we have seen two ways to return response body from resource handler:

1. Returning a string from resource handler function which Luaw returns in turn as a whole response body to the client, and
2. Using Luaw template views that generate response body programmatically in a fashion similar to JSP or ASP

However, Luaw does offer finer grain control over response generation from resource handler should you need it. Remember the resource handler function is passed in both request and response object like this:

```lua
GET '/user/:username' {
	function(req, resp, pathParams)
		return "Hello "..pathParams.username.."!"
	end
}
```

Finer grained control over response generation is achieved by invoking various methods on the response object as described below.

1. `resp:setStatus(status)`: You can set HTTP status code to be returned to the client - 200, 404 etc. - using this method

2. `resp:addHeader(name, value)`: You can add arbitrary HTTP headers to the response using this method. All the headers must be added before you start adding body content.

3. `resp:startStreaming()`: Calling this method activates a special [HTTP 1.1 chunked transfer mode](http://en.wikipedia.org/wiki/Chunked_transfer_encoding) which causes Luaw to stream response to the connected client instead of buffering it in memory till end and then sending it in a single shot. In this mode, any body content added to the response is buffered till it reaches a certain , relatively small buffer size threshold - 2K by default whihch is configurable using property "connection_buffer_size" in server.cfg's luaw_server_config section - and then is sent to the client as a HTTP 1.1 compliant body chunk. This means server does not have to buffer the entire response body in its memory to calculate "Content-Length" header value before it can send it to the client. Thus, this mode improves overall server memory footprint and also client's response time to the first byte received. Luaw template views use this mode by default to generate content. HTTP status and all the HTTP headers must be added to response before resp:startStreaming() is called.

3. `resp:appendBody(content)`: You can use this method to add content to the response body in piecemeal fashion. Depending upon whether the response is in default HTTP 1.1 mode or put in HTTP 1.1 chunked transfer mode by calling resp:startStreaming(); the content is either buffered till resp:flush() is called or streamed to the client in HTTP 1.1 chunks whenever buffered content reaches size limit specified by connection_buffer_size.

4. `resp:flush()`: Causes the response to be flushed to the client. In default (HTTP 1.1) mode this causes Luaw to calculate correct "Content-Length" header value for the whole response buffered so far in the memory and then send it to the client along with the "Content-Length" header. In case the response object was put in the HTTP 1.1 chunked transfer mode by calling resp:startStreaming() this causes Luaw to send the last HTTP chunk followed by the terminating chunk as required by the HTTP 1.1 specification.

5. `resp:close()`: Finally, call this method to actually close underlying connection to client and release all the associated resources.
