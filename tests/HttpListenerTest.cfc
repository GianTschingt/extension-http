/**
 * LDEV-3779 the listener of the tag http (before, after, error) with the engine of the extension. The listener is
 * part of the tag in Lucee and does not depend on the engine, these tests check that what a listener changes in
 * the request (headers HttpClient sets itself, credentials, params) is what the engine sends on the wire, and that
 * what the engine answers is what the listener gets, against a server that records what was sent.
 */
component extends="org.lucee.cfml.test.LuceeTestCase" labels="http" {

	variables.CRLF = chr( 13 ) & chr( 10 );

	function run( testResults, testBox ) {

		describe( "HTTP extension: listener of the tag http (LDEV-3779)", function() {

			it( title="the extension is the engine of these tests", body=function( currentSpec ) {
				expect( createObject( "java", "lucee.commons.net.http.HTTPEngine" ).getEngine().getName() ).toBe( "httpclient5" );
			});

			it( title="without a listener the request is sent as before", body=function( currentSpec ) {
				var srv = new _RecordingServer( [ rsp( 200, "OK", [], "plain" ) ] );
				http url="#srv.getBaseUrl()#/plain" result="local.res";
				var requests = srv.stop();
				expect( res.fileContent ).toBe( "plain" );
				expect( requests.len() ).toBe( 1 );
				expect( srv.headerValues( requests[ 1 ], "X-Ext-Listener" ) ).toBe( [] );
			});

			it( title="before can change url, method, headers and url params of the request the engine sends", body=function( currentSpec ) {
				var srv = new _RecordingServer( [ rsp( 200, "OK", [], "changed" ) ] );
				var base = srv.getBaseUrl();
				http url="#base#/original" method="GET" result="local.res" listener={
					before: function( args, caller ) {
						args.url = base & "/changed";
						args.method = "POST";
						arrayAppend( args.params, { type: "header", name: "X-Ext-Listener", value: "before" } );
						arrayAppend( args.params, { type: "url", name: "q", value: "1" } );
						arrayAppend( args.params, { type: "formfield", name: "f", value: "v" } );
						return arguments;
					}
				};
				var requests = srv.stop();
				expect( res.fileContent ).toBe( "changed" );
				expect( requests.len() ).toBe( 1 );
				expect( requests[ 1 ].line ).toBe( "POST /changed?q=1 HTTP/1.1" );
				expect( srv.headerValues( requests[ 1 ], "X-Ext-Listener" ) ).toBe( [ "before" ] );
				expect( requests[ 1 ].body ).toBe( "f=v" );
			});

			it( title="a Host header added by before is sent like it is set", body=function( currentSpec ) {
				var srv = new _RecordingServer( [ rsp( 200, "OK", [], "host" ) ] );
				http url="#srv.getBaseUrl()#/host" result="local.res" listener={
					before: function( args, caller ) {
						arrayAppend( args.params, { type: "header", name: "Host", value: "listener.example.test" } );
						return arguments;
					}
				};
				var requests = srv.stop();
				expect( srv.headerValues( requests[ 1 ], "Host" ) ).toBe( [ "listener.example.test" ] );
			});

			it( title="a Connection header added by before is sent like it is set", body=function( currentSpec ) {
				var srv = new _RecordingServer( [ rsp( 200, "OK", [], "connection" ) ] );
				http url="#srv.getBaseUrl()#/connection" result="local.res" listener={
					before: function( args, caller ) {
						arrayAppend( args.params, { type: "header", name: "Connection", value: "close" } );
						return arguments;
					}
				};
				var requests = srv.stop();
				expect( srv.headerValues( requests[ 1 ], "Connection" ) ).toBe( [ "close" ] );
			});

			it( title="before can set the credentials, the engine sends Basic with preauth", body=function( currentSpec ) {
				var srv = new _RecordingServer( [ rsp( 200, "OK", [], "basic" ) ] );
				http url="#srv.getBaseUrl()#/basic" preauth=true result="local.res" listener={
					before: function( args, caller ) {
						args.username = "listenerUser";
						args.password = "listenerPass";
						return arguments;
					}
				};
				var requests = srv.stop();
				expect( requests.len() ).toBe( 1 );
				expect( srv.headerValues( requests[ 1 ], "Authorization" ) ).toBe( [ "Basic " & toBase64( "listenerUser:listenerPass" ) ] );
			});

			it( title="before can send back only the changed arguments", body=function( currentSpec ) {
				var srv = new _RecordingServer( [ rsp( 200, "OK", [], "partial" ) ] );
				var base = srv.getBaseUrl();
				http url="#base#/original" result="local.res" listener={
					before: function( args, caller ) {
						return { url: base & "/partial", method: "DELETE" };
					}
				};
				var requests = srv.stop();
				expect( requests[ 1 ].line ).toBe( "DELETE /partial HTTP/1.1" );
				expect( res.fileContent ).toBe( "partial" );
			});

			it( title="before can answer the request, nothing is sent", body=function( currentSpec ) {
				var srv = new _RecordingServer( [] );
				http url="#srv.getBaseUrl()#/cached" result="local.res" listener={
					before: function( args, caller ) {
						return { result: { fileContent: "from local cache", statusCode: "200 OK" } };
					}
				};
				var requests = srv.stop();
				expect( res.fileContent ).toBe( "from local cache" );
				expect( requests.len() ).toBe( 0 );
			});

			it( title="after gets the result of the engine and can modify it", body=function( currentSpec ) {
				var srv = new _RecordingServer( [ rsp( 201, "Created", [ "X-Ext-Answer: yes" ], "created" ) ] );
				var seen = {};
				http url="#srv.getBaseUrl()#/after" result="local.res" listener={
					after: function( args, caller, result ) {
						seen.content = result.fileContent;
						seen.status = result.status_code;
						seen.header = result.responseHeader[ "X-Ext-Answer" ];
						result.fileContent = ucase( result.fileContent );
						return { result: result };
					}
				};
				srv.stop();
				expect( seen.content ).toBe( "created" );
				expect( seen.status ).toBe( 201 );
				expect( seen.header ).toBe( "yes" );
				expect( res.fileContent ).toBe( "CREATED" );
				expect( res.status_code ).toBe( 201 );
			});

			it( title="after gets the arguments of the tag and the result of the redirect the engine followed", body=function( currentSpec ) {
				var srv = new _RecordingServer( [
					rsp( 302, "Found", [ "Location: http://127.0.0.1:{port}/target" ], "" ),
					rsp( 200, "OK", [], "target" )
				] );
				var seen = {};
				http url="#srv.getBaseUrl()#/start" result="local.res" listener={
					after: function( args, caller, result ) {
						seen.url = args.url;
						seen.content = result.fileContent;
					}
				};
				var requests = srv.stop();
				expect( requests.len() ).toBe( 2 );
				expect( seen.url ).toBe( srv.getBaseUrl() & "/start" );
				expect( seen.content ).toBe( "target" );
			});

			it( title="error handles the status of the server the engine got", body=function( currentSpec ) {
				var srv = new _RecordingServer( [ rsp( 500, "Internal Server Error", [], "boom" ) ] );
				var seen = {};
				var afterCalled = { value: false };
				http url="#srv.getBaseUrl()#/error" result="local.res" throwOnError=true listener={
					error: function( args, caller, exception ) {
						seen.message = exception.message;
						return { result: { fileContent: "handled", statusCode: "200 handled" } };
					},
					after: function( args, caller, result ) {
						afterCalled.value = true;
					}
				};
				srv.stop();
				expect( seen.message ).toInclude( "500" );
				expect( res.fileContent ).toBe( "handled" );
				expect( afterCalled.value ).toBeTrue();
			});

			it( title="error handles a connection that is closed without an answer", body=function( currentSpec ) {
				var srv = new _RecordingServer( [ "CLOSE" ] );
				var seen = { called: false };
				http url="#srv.getBaseUrl()#/closed" result="local.res" throwOnError=true listener={
					error: function( args, caller, exception ) {
						seen.called = true;
						return { result: { fileContent: "closed handled", statusCode: "200 handled" } };
					}
				};
				srv.stop();
				expect( seen.called ).toBeTrue();
				expect( res.fileContent ).toBe( "closed handled" );
			});

			it( title="the exception the engine threw is thrown when error does not return a result", body=function( currentSpec ) {
				var srv = new _RecordingServer( [ rsp( 500, "Internal Server Error", [], "boom" ) ] );
				var called = { error: false };
				var msg = "";
				try {
					http url="#srv.getBaseUrl()#/error" result="local.res" throwOnError=true listener={
						error: function( args, caller, exception ) {
							called.error = true;
						}
					};
				}
				catch ( any e ) {
					msg = e.message;
				}
				srv.stop();
				expect( called.error ).toBeTrue();
				expect( msg ).toInclude( "500" );
			});

			it( title="an exception of the listener is not swallowed and nothing is sent", body=function( currentSpec ) {
				var srv = new _RecordingServer( [] );
				var msg = "";
				try {
					http url="#srv.getBaseUrl()#/boom" result="local.res" listener={
						before: function( args, caller ) {
							throw( message="LDEV-3779 listener failure" );
						}
					};
				}
				catch ( any e ) {
					msg = e.message;
				}
				var requests = srv.stop();
				expect( msg ).toBe( "LDEV-3779 listener failure" );
				expect( requests.len() ).toBe( 0 );
			});

			it( title="a component can be the listener", body=function( currentSpec ) {
				var srv = new _RecordingServer( [ rsp( 200, "OK", [], "cfc" ) ] );
				http url="#srv.getBaseUrl()#/cfc" result="local.res" listener=new listener.Listener();
				var requests = srv.stop();
				expect( res.fileContent ).toBe( "[cfc]" );
				expect( srv.headerValues( requests[ 1 ], "X-Ext-Listener" ) ).toBe( [ "component" ] );
			});

			it( title="a function can be the listener, it is the after", body=function( currentSpec ) {
				var srv = new _RecordingServer( [ rsp( 200, "OK", [], "udf" ) ] );
				http url="#srv.getBaseUrl()#/udf" result="local.res" listener=function( args, caller, result ) {
					result.fileContent = "after:" & result.fileContent;
					return { result: result };
				};
				srv.stop();
				expect( res.fileContent ).toBe( "after:udf" );
			});

		});

		describe( "HTTP extension: listener of the application (LDEV-3779)", function() {

			it( title="this.http.listener of the Application.cfc is used for the request of the engine", body=function( currentSpec ) {
				var srv = new _RecordingServer( [ rsp( 200, "OK", [], "app" ) ] );
				var result = _InternalRequest( template=listenerUri( "index.cfm" ), urls={ target: srv.getBaseUrl() & "/app" } );
				var requests = srv.stop();
				expect( result.filecontent.trim() ).toBe( "app|application-after" );
				expect( requests.len() ).toBe( 1 );
				expect( srv.headerValues( requests[ 1 ], "X-Ext-Listener" ) ).toBe( [ "application" ] );
			});

		});

	}

	// the Application.cfc of the directory listener sets this.http.listener, the request needs the web path of it, the test
	// runner maps the directory of the tests with the first part of the name of this component
	private string function listenerUri( required string template ) {
		return "/" & listFirst( getMetadata( this ).name, "." ) & "/listener/" & arguments.template;
	}

	private string function rsp( required numeric status, required string text, array headers=[], string body="" ) {
		var str = "HTTP/1.1 #arguments.status# #arguments.text#" & CRLF;
		for ( var h in arguments.headers ) str &= h & CRLF;
		var len = arrayLen( charsetDecode( arguments.body, "utf-8" ) );
		str &= "Content-Length: #len#" & CRLF & "Connection: close" & CRLF & CRLF & arguments.body;
		return str;
	}

}
