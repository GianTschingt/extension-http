<cfscript>
	// the request of the test, the listener comes from the Application.cfc
	http url=url.target result="local.rsp";
	writeOutput( local.rsp.fileContent );
</cfscript>
