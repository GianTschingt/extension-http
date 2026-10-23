/**
 * a minimal HTTP server for the tests, it answers every connection with the next of the given responses and
 * records the requests it got, so a test can check what the engine has sent exactly (headers HttpClient sets
 * itself, the steps of an authentication, the CONNECT of a proxy tunnel).
 *
 * a response is a string or binary with the raw response (status line, headers, body) or "CLOSE" to close the
 * connection after reading the request without answering. Every response closes the connection.
 */
component {

	public function init( required array responses ) {
		variables.responses = arguments.responses;
		variables.requests = [];
		variables.stopped = false;
		variables.failure = "";
		variables.server = createObject( "java", "java.net.ServerSocket" ).init(
			javacast( "int", 0 ), javacast( "int", 50 ), createObject( "java", "java.net.InetAddress" ).getByName( "127.0.0.1" ) );
		variables.server.setSoTimeout( javacast( "int", 30000 ) );
		variables.port = variables.server.getLocalPort();
		variables.threadName = "recordingServer" & replace( createUUID(), "-", "", "all" );

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
	 * stops the server (when it did not get all the requests it expected) and returns the recorded requests,
	 * an error of the server is thrown here, so a test can not miss it
	 */
	public array function stop() {
		variables.stopped = true;
		variables.server.close();
		threadJoin( variables.threadName, 30000 );
		if ( len( variables.failure ) ) throw( message="the recording server failed: " & variables.failure );
		return variables.requests;
	}

	public void function _serve() {
		try {
			for ( var response in variables.responses ) {
				var socket = variables.server.accept();
				try {
					socket.setSoTimeout( javacast( "int", 10000 ) );
					arrayAppend( variables.requests, readRequest( socket.getInputStream() ) );
					if ( isSimpleValue( response ) && response == "CLOSE" ) continue;
					var out = socket.getOutputStream();
					out.write( isBinary( response ) ? response : charsetDecode( replace( response, "{port}", variables.port, "all" ), "utf-8" ) );
					out.flush();
				}
				finally {
					socket.close();
				}
			}
		}
		catch ( any e ) {
			// a server that is stopped before all responses are used ends with an exception of the closed socket
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
			if ( last4 == chr( 13 ) & chr( 10 ) & chr( 13 ) & chr( 10 ) ) break;
		}
		var lines = listToArray( head.toString( "iso-8859-1" ), chr( 13 ) & chr( 10 ), false, true );
		var req = { "line": arrayLen( lines ) ? lines[ 1 ] : "", "headers": [], "body": "" };
		var length = 0;
		for ( var i = 2; i <= arrayLen( lines ); i++ ) {
			var name = trim( listFirst( lines[ i ], ":" ) );
			var value = trim( listRest( lines[ i ], ":" ) );
			arrayAppend( req.headers, { "name": name, "value": value } );
			if ( name == "Content-Length" ) length = value;
		}
		if ( length > 0 ) {
			req.body = charsetEncode( arguments.is.readNBytes( javacast( "int", length ) ), "utf-8" );
		}
		return req;
	}

	/**
	 * the values of the header in the request, the names are compared without case
	 */
	public array function headerValues( required struct req, required string name ) {
		var values = [];
		for ( var h in arguments.req.headers ) {
			if ( h.name == arguments.name ) arrayAppend( values, h.value );
		}
		return values;
	}
}
