component {

	this.name = "ExtHttpListener-" & hash( getCurrentTemplatePath() );

	this.http.listener = {
		before: function( args, caller ) {
			arrayAppend( args.params, { type: "header", name: "X-Ext-Listener", value: "application" } );
			return arguments;
		},
		after: function( args, caller, result ) {
			result.fileContent &= "|application-after";
			return { result: result };
		}
	};

}
