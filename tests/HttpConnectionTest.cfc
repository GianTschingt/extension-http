/**
 * LDEV-2675 the result of cfhttp has a key "connection" that tells if the connection of the response was taken from
 * the pool, and the stats of the pool for the route of the request. The key is built by the cfhttp tag of Lucee from
 * the data of the engine, these tests check it with the engine of the extension against a server that keeps the
 * connection open and counts the connections it accepts, so what the key says is compared with what the server saw.
 */
component extends="org.lucee.cfml.test.LuceeTestCase" labels="http" {

	variables.CRLF = chr( 13 ) & chr( 10 );

	function run( testResults, testBox ) {
		describe( "HTTP extension: the connection key of the result (LDEV-2675)", function() {

			it( title="the first request uses a new connection, the next request to the same host reuses it", body=function( currentSpec ) {
				var srv = new _KeepAliveServer();
				http url="#srv.getBaseUrl()#/first" timeout=10 result="local.first";
				http url="#srv.getBaseUrl()#/second" timeout=10 result="local.second";
				srv.stop();

				expect( first.filecontent ).toBe( "ok" );
				expect( first ).toHaveKey( "connection" );
				expect( first.connection.pooled ).toBeTrue();
				expect( first.connection.reused ).toBeFalse();
				expect( first.connection.requests ).toBe( 1 );

				expect( second.filecontent ).toBe( "ok" );
				expect( second.connection.pooled ).toBeTrue();
				expect( second.connection.reused ).toBeTrue();
				expect( second.connection.requests ).toBe( 2 );

				// what the server saw
				expect( srv.getConnections() ).toBe( 1 );
			});

			it( title="has the stats of the pool for the route as numbers", body=function( currentSpec ) {
				var srv = new _KeepAliveServer();
				http url="#srv.getBaseUrl()#/" timeout=10 result="local.res";
				srv.stop();

				var c = res.connection;
				expect( c.route ).toBe( "127.0.0.1:#srv.getPort()#" );
				for ( var key in [ "leased", "available", "pending", "max", "requests" ] ) {
					expect( c ).toHaveKey( key );
					expect( isNumeric( c[ key ] ) ).toBeTrue( "[#key#] is not a number: #c[ key ]#" );
				}
				// the connection of the response is in use while the response is read
				expect( c.leased ).toBe( 1 );
				expect( c.available ).toBe( 0 );
				expect( c.pending ).toBe( 0 );
				expect( c.max ).toBeGTE( 1 );
			});

			it( title="a request without pooling is reported as not pooled and has no pool stats", body=function( currentSpec ) {
				var srv = new _KeepAliveServer();
				http url="#srv.getBaseUrl()#/first" pooling=false timeout=10 result="local.first";
				http url="#srv.getBaseUrl()#/second" pooling=false timeout=10 result="local.second";
				srv.stop();

				for ( var res in [ first, second ] ) {
					expect( res.filecontent ).toBe( "ok" );
					expect( res.connection.pooled ).toBeFalse();
					expect( res.connection.reused ).toBeFalse();
					expect( res.connection.requests ).toBe( 1 );
					expect( res.connection ).notToHaveKey( "leased" );
					expect( res.connection ).notToHaveKey( "available" );
					expect( res.connection ).notToHaveKey( "pending" );
					expect( res.connection ).notToHaveKey( "max" );
				}
				// every request had a connection of its own
				expect( srv.getConnections() ).toBe( 2 );
			});

			it( title="a connection the server has closed is not reused, the next request gets a new one", body=function( currentSpec ) {
				var srv = new _KeepAliveServer( [
					"HTTP/1.1 200 OK" & CRLF & "Content-Length: 2" & CRLF & "Connection: close" & CRLF & CRLF & "ok"
				] );
				http url="#srv.getBaseUrl()#/first" timeout=10 result="local.first";
				http url="#srv.getBaseUrl()#/second" timeout=10 result="local.second";
				srv.stop();

				expect( first.connection.reused ).toBeFalse();
				expect( second.connection.pooled ).toBeTrue();
				expect( second.connection.reused ).toBeFalse();
				expect( second.connection.requests ).toBe( 1 );
				expect( srv.getConnections() ).toBe( 2 );
			});

			it( title="a redirect that uses the connection of the call again is not a reuse from the pool", body=function( currentSpec ) {
				var srv = new _KeepAliveServer( [
					"HTTP/1.1 302 Found" & CRLF & "Location: http://127.0.0.1:{port}/target" & CRLF & "Content-Length: 0" & CRLF & CRLF
				] );
				http url="#srv.getBaseUrl()#/start" redirect=true timeout=10 result="local.res";
				srv.stop();

				expect( res.filecontent ).toBe( "ok" );
				// the second exchange of the call used the connection of the first one, a new connection
				expect( srv.getConnections() ).toBe( 1 );
				expect( res.connection.reused ).toBeFalse();
				expect( res.connection.requests ).toBe( 2 );
			});

			it( title="a call that follows a redirect on a connection of an earlier call is reported as reused", body=function( currentSpec ) {
				var srv = new _KeepAliveServer( [
					"HTTP/1.1 200 OK" & CRLF & "Content-Length: 2" & CRLF & CRLF & "ok",
					"HTTP/1.1 302 Found" & CRLF & "Location: http://127.0.0.1:{port}/target" & CRLF & "Content-Length: 0" & CRLF & CRLF
				] );
				http url="#srv.getBaseUrl()#/warmup" timeout=10 result="local.warmup";
				http url="#srv.getBaseUrl()#/start" redirect=true timeout=10 result="local.res";
				srv.stop();

				expect( warmup.connection.reused ).toBeFalse();
				expect( srv.getConnections() ).toBe( 1 );
				expect( res.connection.reused ).toBeTrue();
				expect( res.connection.requests ).toBe( 3 );
			});

		});
	}
}
