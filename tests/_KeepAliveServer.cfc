/**
 * a minimal HTTP server for the tests that keeps the connection open after a response, so a client can send the next
 * request on the same connection. It answers every GET with 200, serves one connection after the other and counts the
 * connections it accepted. An error of the server is thrown by stop(), so a test can not miss it.
 */
component {

	public function init() {
		variables.CRLF = chr( 13 ) & chr( 10 );
		variables.stopped = false;
		variables.failure = "";
		variables.connections = 0;
		variables.socket = javacast( "null", "" );
		variables.server = createObject( "java", "java.net.ServerSocket" ).init(
			javacast( "int", 0 ), javacast( "int", 50 ), createObject( "java", "java.net.InetAddress" ).getByName( "127.0.0.1" ) );
		variables.server.setSoTimeout( javacast( "int", 30000 ) );
		variables.port = variables.server.getLocalPort();
		variables.threadName = "keepAliveServer" & replace( createUUID(), "-", "", "all" );

		thread name="#variables.threadName#" action="run" {
			_serve();
		}
		return this;
	}

	public numeric function getPort() {
		return variables.port;
	}

	public string function getBaseUrl() {
		return "http://127.0.0.1:#variables.port#";
	}

	/**
	 * the number of the connections the server accepted so far
	 */
	public numeric function getConnectionCount() {
		return variables.connections;
	}

	public void function stop() {
		variables.stopped = true;
		variables.server.close();
		// the connection that is kept open
		if ( !isNull( variables.socket ) ) variables.socket.close();
		threadJoin( variables.threadName, 30000 );
		if ( len( variables.failure ) ) throw( message="the keep alive server failed: " & variables.failure );
	}

	public void function _serve() {
		try {
			while ( !variables.stopped ) {
				variables.socket = variables.server.accept();
				variables.connections++;
				variables.socket.setSoTimeout( javacast( "int", 10000 ) );
				var input = variables.socket.getInputStream();
				var output = variables.socket.getOutputStream();
				// one request after the other, until the client closes the connection
				while ( readRequest( input ) ) {
					output.write( charsetDecode( "HTTP/1.1 200 OK" & CRLF & "Content-Length: 2" & CRLF & "Connection: keep-alive" & CRLF & CRLF & "ok", "utf-8" ) );
					output.flush();
				}
				variables.socket.close();
			}
		}
		catch ( any e ) {
			// closing the server and the connection in stop() ends the loop with an error, that is not a failure
			if ( !variables.stopped ) variables.failure = e.message;
		}
	}

	// reads up to the end of the head of the request (the requests of the tests have no body), false when the client closed the connection
	private boolean function readRequest( required any input ) {
		var matched = 0;
		var end = [ 13, 10, 13, 10 ];
		var first = true;
		while ( matched < 4 ) {
			var b = arguments.input.read();
			if ( b == -1 ) {
				if ( first ) return false;
				throw( message="the connection was closed in the middle of a request" );
			}
			first = false;
			matched = ( b == end[ matched + 1 ] ) ? matched + 1 : ( b == 13 ? 1 : 0 );
		}
		return true;
	}
}
