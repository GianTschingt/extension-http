/**
 * LDEV-2822 an HTTP call has an entry in the section "HTTP" of the debugging output: method, host and path (never the
 * query string or the user info), status code, duration and whether the connection was reused. Without debugging there
 * is no entry. The entries are read from the debugger of the request, the same data the debugging templates show.
 */
component extends="org.lucee.cfml.test.LuceeTestCase" labels="http" {

	variables.CRLF = chr( 13 ) & chr( 10 );

	function run( testResults, testBox ) {
		describe( "HTTP extension: the debugging entry of an HTTP call (LDEV-2822)", function() {

			it( title="with debugging there is one entry with method, host, path, status and duration", body=function( currentSpec ) {
				var srv = new _RecordingServer( [ rsp( 200, "OK", [], "ok" ) ] );
				var added = withDebugging( true, function() {
					http url="#srv.getBaseUrl()#/ldev2822/path" result="local.res";
				});
				srv.stop();
				expect( added ).toHaveLength( 1 );
				var name = added.keyArray()[ 1 ];
				expect( name ).toMatch( "^##\d+ GET 127\.0\.0\.1:#srv.getPort()#/ldev2822/path$" );
				expect( added[ name ] ).toMatch( "^200, \d+ ms, new connection$" );
			});

			it( title="the method is the method of the call", body=function( currentSpec ) {
				var srv = new _RecordingServer( [ rsp( 200, "OK", [], "ok" ) ] );
				var added = withDebugging( true, function() {
					http url="#srv.getBaseUrl()#/post" method="POST" result="local.res" {
						httpparam type="formfield" name="a" value="1";
					}
				});
				srv.stop();
				expect( added ).toHaveLength( 1 );
				expect( added.keyArray()[ 1 ] ).toMatch( " POST 127\.0\.0\.1:#srv.getPort()#/post$" );
			});

			it( title="the query string, the user info, the matrix parameters and the fragment are not in the entry", body=function( currentSpec ) {
				var srv = new _RecordingServer( [ rsp( 200, "OK", [], "ok" ) ] );
				var added = withDebugging( true, function() {
					http url="http://user:secretpw@127.0.0.1:#srv.getPort()#/a;jsessionid=secretid/b?token=secrettoken&x=1##secretfragment" result="local.res";
				});
				srv.stop();
				expect( added ).toHaveLength( 1 );
				var name = added.keyArray()[ 1 ];
				expect( name ).toMatch( " GET 127\.0\.0\.1:#srv.getPort()#/a/b$" );
				var all = serializeJSON( added );
				expect( all ).notToInclude( "secret" );
				expect( all ).notToInclude( "user" );
				expect( all ).notToInclude( "token" );
			});

			it( title="the status code of the response is in the entry", body=function( currentSpec ) {
				var srv = new _RecordingServer( [ rsp( 404, "Not Found", [], "nope" ) ] );
				var added = withDebugging( true, function() {
					http url="#srv.getBaseUrl()#/missing" result="local.res";
				});
				srv.stop();
				expect( added ).toHaveLength( 1 );
				expect( added[ added.keyArray()[ 1 ] ] ).toMatch( "^404, \d+ ms" );
			});

			it( title="a call with redirects is one entry with the status of the last response", body=function( currentSpec ) {
				var srv = new _RecordingServer( [
					rsp( 302, "Found", [ "Location: /ldev2822/target" ] ),
					rsp( 200, "OK", [], "ok" )
				] );
				var added = withDebugging( true, function() {
					http url="#srv.getBaseUrl()#/ldev2822/start" result="local.res";
				});
				var requests = srv.stop();
				expect( requests ).toHaveLength( 2 );
				expect( added ).toHaveLength( 1 );
				var name = added.keyArray()[ 1 ];
				expect( name ).toMatch( " GET 127\.0\.0\.1:#srv.getPort()#/ldev2822/start$" );
				expect( added[ name ] ).toMatch( "^200, \d+ ms, new connection$" );
			});

			it( title="a call that fails has an entry with the error", body=function( currentSpec ) {
				// nothing listens on the port 1
				var added = withDebugging( true, function() {
					http url="http://127.0.0.1:1/ldev2822/refused" result="local.res";
				});
				expect( added ).toHaveLength( 1 );
				var name = added.keyArray()[ 1 ];
				expect( name ).toMatch( " GET 127\.0\.0\.1:1/ldev2822/refused$" );
				expect( added[ name ] ).toMatch( "^failed \(HttpHostConnectException\), \d+ ms$" );
			});

			it( title="every call has its own entry, also the calls to the same URL", body=function( currentSpec ) {
				var srv = new _RecordingServer( [ rsp( 200, "OK", [], "one" ), rsp( 200, "OK", [], "two" ) ] );
				var added = withDebugging( true, function() {
					http url="#srv.getBaseUrl()#/same" result="local.res";
					http url="#srv.getBaseUrl()#/same" result="local.res";
				});
				srv.stop();
				expect( added ).toHaveLength( 2 );
				for ( var name in added ) {
					expect( added[ name ] ).toMatch( "^200, \d+ ms" );
				}
			});

			it( title="without debugging there is no entry", body=function( currentSpec ) {
				var srv = new _RecordingServer( [ rsp( 200, "OK", [], "ok" ) ] );
				var added = withDebugging( false, function() {
					http url="#srv.getBaseUrl()#/nodebug" result="local.res";
				});
				var requests = srv.stop();
				expect( requests ).toHaveLength( 1 );
				expect( added ).toBeEmpty();
			});

			it( title="a call that uses a connection of the pool is a reused connection", body=function( currentSpec ) {
				var srv = new _KeepAliveServer();
				try {
					var added = withDebugging( true, function() {
						http url="#srv.getBaseUrl()#/first" result="local.res";
						http url="#srv.getBaseUrl()#/second" result="local.res";
					});
					expect( srv.getConnections() ).toBe( 1 );
				}
				finally {
					srv.stop();
				}
				expect( added ).toHaveLength( 2 );
				for ( var name in added ) {
					if ( name contains "/first" ) expect( added[ name ] ).toMatch( "^200, \d+ ms, new connection$" );
					else expect( added[ name ] ).toMatch( "^200, \d+ ms, connection reused$" );
				}
			});

			it( title="a call without pooling is always a new connection", body=function( currentSpec ) {
				var srv = new _KeepAliveServer();
				try {
					var added = withDebugging( true, function() {
						http url="#srv.getBaseUrl()#/first" pooling=false result="local.res";
						http url="#srv.getBaseUrl()#/second" pooling=false result="local.res";
					});
					expect( srv.getConnections() ).toBe( 2 );
				}
				finally {
					srv.stop();
				}
				expect( added ).toHaveLength( 2 );
				for ( var name in added ) expect( added[ name ] ).toMatch( "^200, \d+ ms, new connection$" );
			});

		});
	}

	/**
	 * runs the body with debugging enabled or disabled for the request and returns the entries of the section HTTP
	 * that the body has added (name and value of the entry), the debugging options of the request are restored
	 */
	private struct function withDebugging( required boolean enabled, required function body ) {
		var ac = getPageContext().getApplicationContext();
		var before = ac.getDebugOptions();
		var existing = entries();
		try {
			setDebugOptions( ac, arguments.enabled ? 1 : 0 );
			arguments.body();
		}
		finally {
			setDebugOptions( ac, before );
		}
		var result = {};
		for ( var name in entries() ) {
			if ( !existing.keyExists( name ) ) result[ name ] = entries()[ name ];
		}
		return result;
	}

	// the entries of the section HTTP of the debugger of the request, the name of the entry and its value
	private struct function entries() {
		var data = getPageContext().getDebugger().getGenericData();
		var result = {};
		if ( isNull( data ) ) return result;
		var section = data.get( "HTTP" );
		if ( isNull( section ) ) return result;
		for ( var name in section.keySet() ) {
			var values = section.get( name );
			// one value per name, the entries of the calls have different names
			if ( values.size() != 1 ) throw( message="the entry [#name#] has [#values.size()#] values: #values.toString()#" );
			result[ name ] = values.get( 0 );
		}
		return result;
	}

	// the debugging options of the application context can only be added or removed one by one
	private void function setDebugOptions( required any ac, required numeric value ) {
		var bit = 1;
		while ( bit <= max( ac.getDebugOptions(), arguments.value ) ) {
			if ( bitAnd( ac.getDebugOptions(), bit ) ) ac.remDebugOptions( bit );
			bit *= 2;
		}
		bit = 1;
		while ( bit <= arguments.value ) {
			if ( bitAnd( arguments.value, bit ) ) ac.setDebugOptions( bit );
			bit *= 2;
		}
	}

	private string function rsp( required numeric status, required string text, array headers=[], string body="" ) {
		var str = "HTTP/1.1 #arguments.status# #arguments.text#" & CRLF;
		for ( var h in arguments.headers ) str &= h & CRLF;
		var len = arrayLen( charsetDecode( arguments.body, "utf-8" ) );
		str &= "Content-Length: #len#" & CRLF & "Connection: close" & CRLF & CRLF & arguments.body;
		return str;
	}
}
