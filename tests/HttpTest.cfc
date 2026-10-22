component extends="org.lucee.cfml.test.LuceeTestCase" labels="http" {

	function run( testResults, testBox ) {
		describe( "HTTP extension", function() {

			it( title="the extension replaces the built-in HTTP engine", body=function( currentSpec ) {
				var engine = createObject( "java", "lucee.commons.net.http.HTTPEngine" ).getEngine();
				expect( engine.getName() ).toBe( "httpclient5" );
			});

			it( title="the extension supports the features the built-in engine can not do", body=function( currentSpec ) {
				var engine = createObject( "java", "lucee.commons.net.http.HTTPEngine" ).getEngine();
				var iface = createObject( "java", "lucee.commons.net.http.HTTPClientEngine" );
				expect( engine.supports( iface.FEATURE_NTLM ) ).toBeTrue();
				expect( engine.supports( iface.FEATURE_RESTRICTED_HEADERS ) ).toBeTrue();
				expect( engine.supports( iface.FEATURE_PREEMPTIVE_AUTH ) ).toBeTrue();
				expect( engine.supports( iface.FEATURE_TLS_OPTIONS ) ).toBeTrue();
				expect( engine.supports( iface.FEATURE_POOL ) ).toBeTrue();
			});

			it( title="the extension does not claim features it does not know", body=function( currentSpec ) {
				var engine = createObject( "java", "lucee.commons.net.http.HTTPEngine" ).getEngine();
				expect( engine.supports( "http3" ) ).toBeFalse();
				expect( engine.supports( "" ) ).toBeFalse();
			});

			it( title="the meta data and the pool stats describe the engine", body=function( currentSpec ) {
				var engine = createObject( "java", "lucee.commons.net.http.HTTPEngine" ).getEngine();
				var md = engine.getMetaData();
				expect( md.engine ).toBe( "httpclient5" );
				expect( md ).toHaveKey( "status" );
				expect( md.config.maxPools ).toBeGT( 0 );
				var stats = engine.getPoolStats();
				expect( stats ).toHaveKey( "leased" );
				expect( stats ).toHaveKey( "routes" );
			});

			it( title="cfhttp works", skip=isDisabled(), body=function( currentSpec ) {
				var hb = server.getTestService( "httpbin" );
				http url="http://#hb.server#:#hb.port#/get" result="local.res";
				expect( res.status_code ).toBe( 200 );
				expect( deserializeJSON( res.filecontent ).url ).toInclude( "/get" );
			});

			it( title="releasing the connections does not break the next requests", skip=isDisabled(), body=function( currentSpec ) {
				var hb = server.getTestService( "httpbin" );
				var engine = createObject( "java", "lucee.commons.net.http.HTTPEngine" ).getEngine();
				http url="http://#hb.server#:#hb.port#/get" result="local.res";
				expect( res.status_code ).toBe( 200 );
				engine.releaseConnections();
				engine.closeIdleConnections();
				http url="http://#hb.server#:#hb.port#/get" result="local.res";
				expect( res.status_code ).toBe( 200 );
			});

			it( title="a connect timeout is a connection failure, not a request time-out", body=function( currentSpec ) {
				http url="http://10.255.255.1/" connectionTimeout=createTimespan( 0, 0, 0, 0, 1 ) result="local.res";
				expect( res.status_code ).toBe( 0 );
			});

		});
	}

	private boolean function isDisabled() {
		return structIsEmpty( server.getTestService( "httpbin" ) );
	}
}
