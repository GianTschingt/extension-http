/**
 * what the extension does that the built-in engine rejects, and how it handles redirects, bodies and
 * responses, checked against a server that records the requests exactly as they were sent
 */
component extends="org.lucee.cfml.test.LuceeTestCase" labels="http" {

	variables.CRLF = chr( 13 ) & chr( 10 );

	function run( testResults, testBox ) {
		describe( "HTTP extension: authentication", function() {

			it( title="NTLM: after the challenge of the server the NTLM negotiation is sent", body=function( currentSpec ) {
				var srv = new _RecordingServer( [
					rsp( 401, "Unauthorized", [ "WWW-Authenticate: NTLM" ] ),
					rsp( 200, "OK", [], "ntlm" )
				] );
				http url="#srv.getBaseUrl()#/ntlm" username="user" password="pass" authType="NTLM" workstation="WS" domain="DOM" result="local.res";
				var requests = srv.stop();
				expect( requests.len() ).toBe( 2 );
				expect( srv.headerValues( requests[ 1 ], "Authorization" ) ).toBeEmpty();
				// type 1 message: "NTLMSSP" followed by the message type 1
				expect( srv.headerValues( requests[ 2 ], "Authorization" )[ 1 ] ).toMatch( "^NTLM TlRMTVNTUAAB" );
				expect( res.status_code ).toBe( 200 );
			});

			it( title="Digest: the credentials are sent as digest after the challenge", body=function( currentSpec ) {
				var srv = new _RecordingServer( [
					rsp( 401, "Unauthorized", [ 'WWW-Authenticate: Digest realm="test", qop="auth", nonce="dcd98b7102dd2f0e8b11d0f600bfb0c093", opaque="5ccc069c403ebaf9f0171e9517f40e41"' ] ),
					rsp( 200, "OK", [], "digest" )
				] );
				http url="#srv.getBaseUrl()#/digest" username="user" password="pass" preauth=false result="local.res";
				var requests = srv.stop();
				expect( requests.len() ).toBe( 2 );
				var auth = srv.headerValues( requests[ 2 ], "Authorization" )[ 1 ];
				expect( auth ).toMatch( "^Digest " );
				expect( auth ).toInclude( 'username="user"' );
				expect( auth ).toInclude( 'realm="test"' );
				expect( auth ).notToInclude( "pass" );
				expect( res.status_code ).toBe( 200 );
			});

			it( title="Basic with preauth: the credentials are sent with the first request", body=function( currentSpec ) {
				var srv = new _RecordingServer( [ rsp( 200, "OK", [], "basic" ) ] );
				http url="#srv.getBaseUrl()#/basic" username="user" password="pass" preauth=true result="local.res";
				var requests = srv.stop();
				expect( requests.len() ).toBe( 1 );
				expect( srv.headerValues( requests[ 1 ], "Authorization" ) ).toBe( [ "Basic " & toBase64( "user:pass" ) ] );
			});

			it( title="Basic without preauth: the credentials are sent after the challenge", body=function( currentSpec ) {
				var srv = new _RecordingServer( [
					rsp( 401, "Unauthorized", [ 'WWW-Authenticate: Basic realm="test"' ] ),
					rsp( 200, "OK", [], "basic" )
				] );
				http url="#srv.getBaseUrl()#/basic" username="user" password="pass" preauth=false result="local.res";
				var requests = srv.stop();
				expect( requests.len() ).toBe( 2 );
				expect( srv.headerValues( requests[ 1 ], "Authorization" ) ).toBeEmpty();
				expect( srv.headerValues( requests[ 2 ], "Authorization" ) ).toBe( [ "Basic " & toBase64( "user:pass" ) ] );
				expect( res.status_code ).toBe( 200 );
			});

			it( title="the credentials are not sent to the host of a redirect", body=function( currentSpec ) {
				var srv = new _RecordingServer( [
					rsp( 302, "Found", [ "Location: http://localhost:{port}/other" ] ),
					rsp( 401, "Unauthorized", [ 'WWW-Authenticate: Basic realm="test"' ] )
				] );
				http url="#srv.getBaseUrl()#/start" username="user" password="pass" preauth=true result="local.res";
				var requests = srv.stop();
				expect( requests.len() ).toBe( 2 );
				expect( srv.headerValues( requests[ 1 ], "Authorization" ) ).toBe( [ "Basic " & toBase64( "user:pass" ) ] );
				expect( srv.headerValues( requests[ 2 ], "Authorization" ) ).toBeEmpty();
				expect( res.status_code ).toBe( 401 );
			});

			it( title="proxy: the credentials are sent with the CONNECT of the tunnel after the proxy asked for them", body=function( currentSpec ) {
				var srv = new _RecordingServer( [
					rsp( 407, "Proxy Authentication Required", [ 'Proxy-Authenticate: Basic realm="proxy"' ] ),
					rsp( 403, "Forbidden", [] )
				] );
				http url="https://lucee.example/" proxyServer="127.0.0.1" proxyPort=srv.getPort() proxyUser="puser" proxyPassword="ppass" result="local.res";
				var requests = srv.stop();
				expect( requests.len() ).toBe( 2 );
				expect( requests[ 1 ].line ).toBe( "CONNECT lucee.example:443 HTTP/1.1" );
				expect( srv.headerValues( requests[ 1 ], "Proxy-Authorization" ) ).toBeEmpty();
				expect( requests[ 2 ].line ).toBe( "CONNECT lucee.example:443 HTTP/1.1" );
				expect( srv.headerValues( requests[ 2 ], "Proxy-Authorization" ) ).toBe( [ "Basic " & toBase64( "puser:ppass" ) ] );
				// the proxy refused the tunnel, as with HttpClient 4 the answer of the proxy is the result, the target was never reached
				expect( res.status_code ).toBe( 403 );
			});

		});

		describe( "HTTP extension: request", function() {

			it( title="the headers the JDK client does not allow (Host, Connection, Expect, Upgrade) are sent as set", body=function( currentSpec ) {
				var srv = new _RecordingServer( [ rsp( 200, "OK", [], "headers" ) ] );
				http url="#srv.getBaseUrl()#/headers" result="local.res" {
					httpparam type="header" name="Host" value="lucee.example";
					httpparam type="header" name="Connection" value="close";
					httpparam type="header" name="Expect" value="100-continue";
					httpparam type="header" name="Upgrade" value="websocket";
				}
				var requests = srv.stop();
				expect( requests.len() ).toBe( 1 );
				expect( srv.headerValues( requests[ 1 ], "Host" ) ).toBe( [ "lucee.example" ] );
				expect( srv.headerValues( requests[ 1 ], "Connection" ) ).toBe( [ "close" ] );
				expect( srv.headerValues( requests[ 1 ], "Expect" ) ).toBe( [ "100-continue" ] );
				expect( srv.headerValues( requests[ 1 ], "Upgrade" ) ).toBe( [ "websocket" ] );
				expect( res.status_code ).toBe( 200 );
			});

			it( title="a Content-Length header of the caller does not break the request, the length comes from the body", body=function( currentSpec ) {
				var srv = new _RecordingServer( [ rsp( 200, "OK", [], "body" ) ] );
				http url="#srv.getBaseUrl()#/body" method="POST" result="local.res" {
					httpparam type="header" name="Content-Length" value="1";
					httpparam type="body" value="hello";
				}
				var requests = srv.stop();
				expect( requests.len() ).toBe( 1 );
				expect( srv.headerValues( requests[ 1 ], "Content-Length" ) ).toBe( [ "5" ] );
				expect( requests[ 1 ].body ).toBe( "hello" );
				expect( res.status_code ).toBe( 200 );
			});

			it( title="a cookie without a domain is sent to the host of the URL", body=function( currentSpec ) {
				var srv = new _RecordingServer( [ rsp( 200, "OK", [], "cookie" ) ] );
				http url="#srv.getBaseUrl()#/cookie" result="local.res" {
					httpparam type="cookie" name="lucee" value="rocks";
				}
				var requests = srv.stop();
				expect( requests.len() ).toBe( 1 );
				expect( srv.headerValues( requests[ 1 ], "Cookie" ) ).toBe( [ "lucee=rocks" ] );
			});

			it( title="a POST is not sent again when the connection was closed without a response", body=function( currentSpec ) {
				var srv = new _RecordingServer( [ "CLOSE", rsp( 200, "OK", [], "second" ) ] );
				http url="#srv.getBaseUrl()#/post" method="POST" result="local.res" {
					httpparam type="body" value="once";
				}
				var requests = srv.stop();
				expect( requests.len() ).toBe( 1 );
				expect( res.status_code ).toBe( 0 );
			});

			it( title="a GET is sent again when the connection was closed without a response", body=function( currentSpec ) {
				var srv = new _RecordingServer( [ "CLOSE", rsp( 200, "OK", [], "second" ) ] );
				http url="#srv.getBaseUrl()#/get" result="local.res";
				var requests = srv.stop();
				expect( requests.len() ).toBe( 2 );
				expect( res.status_code ).toBe( 200 );
				expect( res.filecontent ).toBe( "second" );
			});

			it( title="a POST keeps its method and its body with a redirect 307", body=function( currentSpec ) {
				var file = getTempFile( getTempDirectory(), "exthttp", "txt" );
				fileWrite( file, "from a file" );
				var srv = new _RecordingServer( [
					rsp( 307, "Temporary Redirect", [ "Location: /next" ] ),
					rsp( 200, "OK", [], "done" )
				] );
				http url="#srv.getBaseUrl()#/start" method="POST" redirect=true pooling=false result="local.res" {
					httpparam type="body" value="#fileReadBinary( file )#";
				}
				var requests = srv.stop();
				fileDelete( file );
				expect( requests.len() ).toBe( 2 );
				expect( requests[ 2 ].line ).toBe( "POST /next HTTP/1.1" );
				expect( requests[ 2 ].body ).toBe( "from a file" );
				expect( res.status_code ).toBe( 200 );
			});

		});

		describe( "HTTP extension: response", function() {

			it( title="the URL of the response is the one after the redirects (resolveurl)", body=function( currentSpec ) {
				var srv = new _RecordingServer( [
					rsp( 302, "Found", [ "Location: /sub/page.html" ] ),
					rsp( 200, "OK", [ "Content-Type: text/html" ], '<a href="other.html">other</a>' )
				] );
				http url="#srv.getBaseUrl()#/start.html" resolveurl=true result="local.res";
				var requests = srv.stop();
				expect( requests.len() ).toBe( 2 );
				expect( requests[ 2 ].line ).toBe( "GET /sub/page.html HTTP/1.1" );
				expect( res.filecontent ).toInclude( "#srv.getBaseUrl()#/sub/other.html" );
				expect( res.locations ).toBe( [ "#srv.getBaseUrl()#/sub/page.html" ] );
			});

			it( title="a compressed response is decompressed and its encoding headers are removed", body=function( currentSpec ) {
				var gz = gzip( "hello compressed world" );
				var srv = new _RecordingServer( [ binaryRsp( [ "Content-Type: text/plain; charset=utf-8", "Content-Encoding: gzip" ], gz ) ] );
				http url="#srv.getBaseUrl()#/gzip" result="local.res";
				srv.stop();
				expect( res.filecontent ).toBe( "hello compressed world" );
				expect( res.responseheader ).notToHaveKey( "Content-Encoding" );
			});

			it( title="the response of a HEAD request keeps its Content-Encoding header, there is nothing that was decompressed", body=function( currentSpec ) {
				var srv = new _RecordingServer( [ "HTTP/1.1 200 OK" & CRLF & "Content-Type: text/plain" & CRLF & "Content-Encoding: gzip" & CRLF & "Content-Length: 42" & CRLF & "Connection: close" & CRLF & CRLF ] );
				http url="#srv.getBaseUrl()#/head" method="HEAD" result="local.res";
				var requests = srv.stop();
				expect( requests[ 1 ].line ).toBe( "HEAD /head HTTP/1.1" );
				expect( res.responseheader[ "Content-Encoding" ] ).toBe( "gzip" );
				expect( res.responseheader[ "Content-Length" ] ).toBe( "42" );
			});

			it( title="the length of a response without Content-Length does not consume its content", body=function( currentSpec ) {
				// no Content-Length, the end of the content is the end of the connection
				var srv = new _RecordingServer( [ "HTTP/1.1 200 OK" & CRLF & "Content-Type: text/plain" & CRLF & "Connection: close" & CRLF & CRLF & "content without a length" ] );
				http url="#srv.getBaseUrl()#/nolength" result="local.res";
				srv.stop();
				expect( res.filecontent ).toBe( "content without a length" );
			});

		});
	}

	private string function rsp( required numeric status, required string text, array headers=[], string body="" ) {
		var str = "HTTP/1.1 #arguments.status# #arguments.text#" & CRLF;
		for ( var h in arguments.headers ) str &= h & CRLF;
		var len = arrayLen( charsetDecode( arguments.body, "utf-8" ) );
		str &= "Content-Length: #len#" & CRLF & "Connection: close" & CRLF & CRLF & arguments.body;
		return str;
	}

	private binary function binaryRsp( required array headers, required binary body ) {
		var head = "HTTP/1.1 200 OK" & CRLF;
		for ( var h in arguments.headers ) head &= h & CRLF;
		head &= "Content-Length: #arrayLen( arguments.body )#" & CRLF & "Connection: close" & CRLF & CRLF;
		var out = createObject( "java", "java.io.ByteArrayOutputStream" ).init();
		out.write( charsetDecode( head, "iso-8859-1" ) );
		out.write( arguments.body );
		return out.toByteArray();
	}

	private binary function gzip( required string str ) {
		var bytes = createObject( "java", "java.io.ByteArrayOutputStream" ).init();
		var gz = createObject( "java", "java.util.zip.GZIPOutputStream" ).init( bytes );
		gz.write( charsetDecode( arguments.str, "utf-8" ) );
		gz.close();
		return bytes.toByteArray();
	}
}
