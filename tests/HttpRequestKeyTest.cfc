/**
 * LDEV-2542 the result of cfhttp has a key "request" with the request that was sent, sensitive values are masked.
 * The key is built by the cfhttp tag of Lucee, these tests check it with the engine of the extension against a
 * server that records what was sent on the wire: the key must describe what the server got, the masked values
 * must still be sent with their real value, and the finalUrl must be the one after the redirects of this engine.
 */
component extends="org.lucee.cfml.test.LuceeTestCase" labels="http" {

	variables.CRLF = chr( 13 ) & chr( 10 );

	// nothing listens there, the request key is set before the request is sent
	variables.noServer = "http://127.0.0.1:1/ldev2542";

	function run( testResults, testBox ) {
		// the key exists in the Lucee versions that have LDEV-2542, with an older Lucee there is nothing to test
		var supported = hasRequestKey();

		describe( "HTTP extension: the request key of the result (LDEV-2542)", function() {

			it( title="the extension is the engine of these tests", skip=!supported, body=function( currentSpec ) {
				expect( createObject( "java", "lucee.commons.net.http.HTTPEngine" ).getEngine().getName() ).toBe( "httpclient5" );
			});

			it( title="has the method, url, finalUrl, headers and params", skip=!supported, body=function( currentSpec ) {
				var srv = new _RecordingServer( [ rsp( 200, "OK", [], "ok" ) ] );
				http url="#srv.getBaseUrl()#/get?a=1" result="local.res";
				srv.stop();
				expect( res.request.method ).toBe( "GET" );
				expect( res.request.url ).toBe( "#srv.getBaseUrl()#/get?a=1" );
				expect( res.request.finalUrl ).toBe( res.request.url );
				expect( res.request.headers ).toBeStruct();
				expect( res.request.params.url.a ).toBe( "1" );
				expect( res.request.params.form ).toBeStruct();
				expect( res.request.params.file ).toBeStruct();
				expect( res.request.params.body ).toBeStruct();
			});

			it( title="the headers of the key are the headers the server got, sensitive ones are masked in the key only", skip=!supported, body=function( currentSpec ) {
				var srv = new _RecordingServer( [ rsp( 200, "OK", [], "ok" ) ] );
				http url="#srv.getBaseUrl()#/headers" result="local.res" {
					httpparam type="header" name="X-Ldev2542" value="visible";
					httpparam type="header" name="Authorization" value="Bearer abc123";
					httpparam type="header" name="X-Api-Token" value="abc123";
					httpparam type="header" name="X-Client-Secret" value="abc123";
				}
				var requests = srv.stop();
				expect( requests.len() ).toBe( 1 );
				// on the wire
				expect( srv.headerValues( requests[ 1 ], "X-Ldev2542" ) ).toBe( [ "visible" ] );
				expect( srv.headerValues( requests[ 1 ], "Authorization" ) ).toBe( [ "Bearer abc123" ] );
				expect( srv.headerValues( requests[ 1 ], "X-Api-Token" ) ).toBe( [ "abc123" ] );
				expect( srv.headerValues( requests[ 1 ], "X-Client-Secret" ) ).toBe( [ "abc123" ] );
				// in the key
				expect( res.request.headers[ "X-Ldev2542" ] ).toBe( "visible" );
				expect( res.request.headers[ "Authorization" ] ).toBe( "***" );
				expect( res.request.headers[ "X-Api-Token" ] ).toBe( "***" );
				expect( res.request.headers[ "X-Client-Secret" ] ).toBe( "***" );
				expect( serializeJSON( res.request ) ).notToInclude( "abc123" );
				// every header of the key that is not masked was sent with the same value
				for ( var name in res.request.headers ) {
					if ( res.request.headers[ name ] == "***" ) continue;
					expect( srv.headerValues( requests[ 1 ], name ) ).toBe( [ res.request.headers[ name ] ], "header [#name#]" );
				}
			});

			it( title="Basic with preauth: the key has a masked Authorization header and the server got the credentials", skip=!supported, body=function( currentSpec ) {
				var srv = new _RecordingServer( [ rsp( 200, "OK", [], "basic" ) ] );
				http url="#srv.getBaseUrl()#/basic" username="ldev2542user" password="abc123" preauth=true result="local.res";
				var requests = srv.stop();
				expect( srv.headerValues( requests[ 1 ], "Authorization" ) ).toBe( [ "Basic " & toBase64( "ldev2542user:abc123" ) ] );
				expect( res.request.headers[ "Authorization" ] ).toBe( "***" );
				expect( serializeJSON( res.request ) ).notToInclude( "abc123" );
				expect( serializeJSON( res.request ) ).notToInclude( "ldev2542user" );
				expect( serializeJSON( res.request ) ).notToInclude( toBase64( "ldev2542user:abc123" ) );
			});

			it( title="a cookie param: the key has a masked Cookie header and the server got the cookie", skip=!supported, body=function( currentSpec ) {
				var srv = new _RecordingServer( [ rsp( 200, "OK", [], "cookie" ) ] );
				http url="#srv.getBaseUrl()#/cookie" result="local.res" {
					httpparam type="cookie" name="sid" value="abc123";
				}
				var requests = srv.stop();
				expect( srv.headerValues( requests[ 1 ], "Cookie" ) ).toBe( [ "sid=abc123" ] );
				expect( res.request.headers[ "Cookie" ] ).toBe( "***" );
				expect( serializeJSON( res.request ) ).notToInclude( "abc123" );
			});

			it( title="masks the sensitive params in the url, the server got the real url", skip=!supported, body=function( currentSpec ) {
				var srv = new _RecordingServer( [ rsp( 200, "OK", [], "ok" ) ] );
				http url="#srv.getBaseUrl()#/q?a=1&access_token=abc123&Password=abc123&c=3" result="local.res";
				var requests = srv.stop();
				expect( requests[ 1 ].line ).toBe( "GET /q?a=1&access_token=abc123&Password=abc123&c=3 HTTP/1.1" );
				expect( res.request.url ).toBe( "#srv.getBaseUrl()#/q?a=1&access_token=***&Password=***&c=3" );
				expect( res.request.finalUrl ).toBe( res.request.url );
				expect( res.request.params.url.a ).toBe( "1" );
				expect( res.request.params.url.access_token ).toBe( "***" );
				expect( res.request.params.url.password ).toBe( "***" );
				expect( serializeJSON( res.request ) ).notToInclude( "abc123" );
			});

			// HttpClient 5 refuses a url with user info, the request fails but the key is there and must not show it
			it( title="masks the user info of the url, also when the request fails", skip=!supported, body=function( currentSpec ) {
				http url="http://ldev2542user:abc123@127.0.0.1:1/q?a=1" result="local.res" throwOnError=false;
				expect( res.request.url ).toBe( "http://***@127.0.0.1:1/q?a=1" );
				expect( res.request.finalUrl ).toBe( res.request.url );
				expect( serializeJSON( res.request ) ).notToInclude( "abc123" );
				expect( serializeJSON( res.request ) ).notToInclude( "ldev2542user" );
			});

			it( title="has the form fields, sensitive ones are masked in the key and sent with their value", skip=!supported, body=function( currentSpec ) {
				var srv = new _RecordingServer( [ rsp( 200, "OK", [], "ok" ) ] );
				http url="#srv.getBaseUrl()#/form" method="POST" result="local.res" {
					httpparam type="formfield" name="user" value="susi";
					httpparam type="formfield" name="password" value="abc123";
				}
				var requests = srv.stop();
				expect( requests[ 1 ].body ).toBe( "user=susi&password=abc123" );
				expect( res.request.method ).toBe( "POST" );
				expect( res.request.params.form.user ).toBe( "susi" );
				expect( res.request.params.form.password ).toBe( "***" );
				expect( res.request.headers[ "Content-Type" ] ).toInclude( "application/x-www-form-urlencoded" );
				expect( serializeJSON( res.request ) ).notToInclude( "abc123" );
			});

			it( title="has the files and form fields of a multipart request", skip=!supported, body=function( currentSpec ) {
				var file = getTempFile( getTempDirectory(), "exthttp", "txt" );
				var srv = new _RecordingServer( [ rsp( 200, "OK", [], "ok" ) ] );
				try {
					fileWrite( file, "abc123" );
					http url="#srv.getBaseUrl()#/multipart" method="POST" result="local.res" {
						httpparam type="formfield" name="user" value="susi";
						httpparam type="formfield" name="secret" value="abc123";
						httpparam type="file" name="upload" file="#file#" mimetype="text/plain";
					}
				}
				finally {
					var requests = srv.stop();
					fileDelete( file );
				}
				// the server got a multipart request with the boundary, the key has the content type without it
				expect( srv.headerValues( requests[ 1 ], "Content-Type" )[ 1 ] ).toMatch( "^multipart/form-data; boundary=" );
				expect( res.request.headers[ "Content-Type" ] ).toBe( "multipart/form-data" );
				expect( res.request.params.form.user ).toBe( "susi" );
				expect( res.request.params.form.secret ).toBe( "***" );
				expect( res.request.params.file.upload ).toBe( listLast( file, "/\" ) );
				expect( serializeJSON( res.request ) ).notToInclude( "abc123" );
			});

			it( title="has a summary of the body, not the content", skip=!supported, body=function( currentSpec ) {
				var srv = new _RecordingServer( [ rsp( 200, "OK", [], "ok" ) ] );
				http url="#srv.getBaseUrl()#/body" method="POST" result="local.res" {
					httpparam type="body" value="abc123" mimetype="application/json";
				}
				var requests = srv.stop();
				expect( requests[ 1 ].body ).toBe( "abc123" );
				expect( res.request.params.body.type ).toBe( "text" );
				expect( res.request.params.body.length ).toBe( 6 );
				expect( res.request.params.body.mimetype ).toBe( "application/json" );
				expect( serializeJSON( res.request ) ).notToInclude( "abc123" );
			});

			it( title="finalUrl is the url after a redirect that was followed, url is the requested url", skip=!supported, body=function( currentSpec ) {
				var srv = new _RecordingServer( [
					rsp( 302, "Found", [ "Location: /sub/page.html" ] ),
					rsp( 200, "OK", [], "done" )
				] );
				http url="#srv.getBaseUrl()#/start.html" redirect=true result="local.res";
				var requests = srv.stop();
				expect( requests.len() ).toBe( 2 );
				expect( requests[ 2 ].line ).toBe( "GET /sub/page.html HTTP/1.1" );
				expect( res.status_code ).toBe( 200 );
				expect( res.request.url ).toBe( "#srv.getBaseUrl()#/start.html" );
				expect( res.request.finalUrl ).toBe( "#srv.getBaseUrl()#/sub/page.html" );
			});

			it( title="finalUrl is the url after more than one redirect", skip=!supported, body=function( currentSpec ) {
				var srv = new _RecordingServer( [
					rsp( 301, "Moved Permanently", [ "Location: /one" ] ),
					rsp( 302, "Found", [ "Location: /two?token=abc123" ] ),
					rsp( 200, "OK", [], "done" )
				] );
				http url="#srv.getBaseUrl()#/start" redirect=true result="local.res";
				var requests = srv.stop();
				expect( requests.len() ).toBe( 3 );
				expect( res.request.url ).toBe( "#srv.getBaseUrl()#/start" );
				expect( res.request.finalUrl ).toBe( "#srv.getBaseUrl()#/two?token=***" );
				expect( serializeJSON( res.request ) ).notToInclude( "abc123" );
			});

			it( title="finalUrl is the requested url when the redirect is not followed", skip=!supported, body=function( currentSpec ) {
				var srv = new _RecordingServer( [ rsp( 302, "Found", [ "Location: /other" ] ) ] );
				http url="#srv.getBaseUrl()#/start" redirect=false result="local.res";
				var requests = srv.stop();
				expect( requests.len() ).toBe( 1 );
				expect( res.status_code ).toBe( 302 );
				expect( res.request.finalUrl ).toBe( "#srv.getBaseUrl()#/start" );
				expect( res.request.finalUrl ).toBe( res.request.url );
			});

			it( title="the key is there when the request failed", skip=!supported, body=function( currentSpec ) {
				http url="#variables.noServer#" result="local.res" timeout=5 throwOnError=false;
				expect( res.request.method ).toBe( "GET" );
				expect( res.request.url ).toBe( variables.noServer );
				expect( res.request.finalUrl ).toBe( variables.noServer );
			});

		});
	}

	private boolean function hasRequestKey() {
		http url="#variables.noServer#" result="local.res" timeout=5 throwOnError=false;
		return structKeyExists( res, "request" );
	}

	private string function rsp( required numeric status, required string text, array headers=[], string body="" ) {
		var str = "HTTP/1.1 #arguments.status# #arguments.text#" & CRLF;
		for ( var h in arguments.headers ) str &= h & CRLF;
		var len = arrayLen( charsetDecode( arguments.body, "utf-8" ) );
		str &= "Content-Length: #len#" & CRLF & "Connection: close" & CRLF & CRLF & arguments.body;
		return str;
	}
}
