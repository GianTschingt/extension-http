/**
 * a minimal HTTP server for the tests that keeps the connection open after an answer (HTTP/1.1 keep-alive), so a
 * test can see if the engine uses a connection again. It counts the connections it has accepted and records the
 * requests it got.
 *
 * it answers the n-th request with the n-th of the given responses, and every request after the last one with a
 * "200 OK" with the body "ok". A response is a string with the raw response (status line, headers, body), the
 * connection is closed after a response that has the header "Connection: close", otherwise it stays open.
 * The server handles one connection at a time.
 */
component {

	variables.CRLF = chr( 13 ) & chr( 10 );

	public function init( array responses=[] ) {
		variables.responses = arguments.responses;
		variables.requests = [];
		variables.connections = 0;
		variables.stopped = false;
		variables.failure = "";
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
	 * the number of connections the server has accepted so far
	 */
	public numeric function getConnections() {
		return variables.connections;
	}

	/**
	 * stops the server and returns the recorded requests, an error of the server is thrown here, so a test can not
	 * miss it
	 */
	public array function stop() {
		variables.stopped = true;
		if ( structKeyExists( variables, "active" ) ) variables.active.close();
		variables.server.close();
		threadJoin( variables.threadName, 30000 );
		if ( len( variables.failure ) ) throw( message="the keep alive server failed: " & variables.failure );
		return variables.requests;
	}

	public void function _serve() {
		try {
			while ( !variables.stopped ) {
				var socket = variables.server.accept();
				variables.connections++;
				variables.active = socket;
				try {
					socket.setSoTimeout( javacast( "int", 30000 ) );
					var is = socket.getInputStream();
					var out = socket.getOutputStream();
					while ( true ) {
						var req = readRequest( is );
						// the client closed the connection
						if ( !len( req.line ) ) break;
						arrayAppend( variables.requests, req );
						var n = arrayLen( variables.requests );
						var response = n <= arrayLen( variables.responses ) ? variables.responses[ n ]
							: "HTTP/1.1 200 OK" & variables.CRLF & "Content-Length: 2" & variables.CRLF & variables.CRLF & "ok";
						out.write( charsetDecode( replace( response, "{port}", variables.port, "all" ), "utf-8" ) );
						out.flush();
						if ( findNoCase( "Connection: close", response ) ) break;
					}
				}
				finally {
					socket.close();
				}
			}
		}
		catch ( any e ) {
			// a server that is stopped ends with an exception of the closed socket
			if ( !variables.stopped ) variables.failure = e.message;
		}
		finally {
			variables.server.close();
		}
	}

	private struct function readRequest( required is ) {
		var head = createObject( "java", "java.io.ByteArrayOutputStream" ).init();
		var last4 = "";
		while ( true ) {
			var b = arguments.is.read();
			if ( b == -1 ) break;
			head.write( javacast( "int", b ) );
			last4 = right( last4 & chr( b ), 4 );
			if ( last4 == variables.CRLF & variables.CRLF ) break;
		}
		var lines = listToArray( head.toString( "iso-8859-1" ), variables.CRLF, false, true );
		var req = { "line": arrayLen( lines ) ? lines[ 1 ] : "", "headers": [] };
		for ( var i = 2; i <= arrayLen( lines ); i++ ) {
			arrayAppend( req.headers, { "name": trim( listFirst( lines[ i ], ":" ) ), "value": trim( listRest( lines[ i ], ":" ) ) } );
		}
		return req;
	}
}
