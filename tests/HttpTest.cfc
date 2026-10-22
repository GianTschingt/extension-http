component extends="org.lucee.cfml.test.LuceeTestCase" labels="http" {

	function run( testResults, testBox ) {
		describe( "HTTP extension", function() {

			it( title="the extension replaces the built-in HTTP engine", body=function( currentSpec ) {
				var engine = createObject( "java", "lucee.commons.net.http.HTTPEngine" ).getEngine();
				expect( engine.getName() ).toBe( "httpclient5" );
			});

			it( title="the extension supports what the built-in engine can not do", body=function( currentSpec ) {
				var engine = createObject( "java", "lucee.commons.net.http.HTTPEngine" ).getEngine();
				expect( engine.supports( "ntlm" ) ).toBeTrue();
				expect( engine.supports( "restricted-headers" ) ).toBeTrue();
			});

			it( title="cfhttp works", skip=isDisabled(), body=function( currentSpec ) {
				var hb = server.getTestService( "httpbin" );
				http url="http://#hb.server#:#hb.port#/get" result="local.res";
				// the status depends on the test service, 0 would mean the request did not get a response
				expect( res.status_code ).toBeGT( 0 );
			});

			it( title="a connect timeout is a connection failure, not a request time-out", body=function( currentSpec ) {
				http url="http://10.255.255.1/" connectionTimeout=createTimespan( 0, 0, 0, 0, 1 ) result="local.res";
				expect( res.status_code ).toBe( 0 );
			});

		});
	}

	private boolean function isDisabled() {
		try {
			return structIsEmpty( server.getTestService( "httpbin" ) );
		}
		catch ( any e ) {
			return true;
		}
	}
}
