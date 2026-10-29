# Lucee HTTP Extension

With Lucee 9, Apache HttpClient moved out of the core. The core sends HTTP requests (the tag `cfhttp`, downloads of extensions, the AI engines) with a built-in engine based on `java.net.http`. This extension replaces it with an engine based on Apache HttpClient 5.

Install it when you need what the built-in engine can not do:

* NTLM authentication (`authType="NTLM"` with `domain`)
* Digest authentication (the scheme the server asks for, Digest before Basic)
* Basic authentication at a proxy for a HTTPS request (the credentials are sent with the `CONNECT` of the tunnel)
* setting the headers the JDK does not allow to set (`Host`, `Connection`, `Expect`, `Upgrade`)
* the connection pool and its statistics (`getSystemInfo()`)
* separate connect and socket timeouts, retry of an idempotent request (GET, HEAD, ...) when a pooled connection was closed by the server, a POST is never retried

Without the extension, a request that needs one of these fails with a message that names this extension.

Behaviour:

* Redirects are followed as with the built-in engine: 301, 302 and 303 change the method to GET (except GET and HEAD), 307 and 308 keep the method and the body; credentials are only sent to the host of the request URL, not to the host of a redirect. A 307/308 of a request with a body read from a stream (it can not be sent twice) fails with a clear message.
* A `Content-Length` header param is ignored, as with the built-in engine, the length comes from the body.
* A response with `Content-Encoding` (gzip, deflate) is decoded, the headers `Content-Encoding`, `Content-Length` and `Content-MD5` are then removed from the result, because they describe the encoded body. The response of a HEAD request keeps them.
* The result of `cfhttp` has a key `request` with the request that was sent (`method`, `url`, `finalUrl`, `headers`, `params`), values of sensitive headers, params and the user info of the URL are masked with `***` ([LDEV-2542](https://luceeserver.atlassian.net/browse/LDEV-2542)). Lucee builds the key, the same for every engine, `finalUrl` is the URL after the redirects this engine followed. It needs a Lucee version that has LDEV-2542.
* When a proxy refuses the tunnel for a HTTPS request, the response of the proxy is the result (as with HttpClient 4).
* NTLM uses the NTLM implementation of HttpClient 5, which HttpClient 5 marks as deprecated, and HttpClient 5.6 ignores the `workstation`.
* Each combination of client certificate and trust store gets its own connection pool (at most 64, the least recently used is closed when its connections are idle), the trust store is the same as for the built-in engine.

The "lite" extension (`*.lite.lex`) has no `maven/` folder, Lucee loads the bundled libraries from Maven, the same as for the other Lucee extensions.

Differences to Lucee 8: Apache HttpClient 5 sends no `Content-Transfer-Encoding` header for the parts of a multipart request (RFC 7578 says to omit it), and some error messages differ.

Issues: https://luceeserver.atlassian.net/browse/LDEV-6677

## Versioning and releases

Works like Lucee core (LDEV-6516): every code change gets its own version number. The version is not edited by hand.
`pom.xml` uses a CI-friendly `${revision}` built from `extension.version.base`, a build number and
`extension.version.qualifier` (`-SNAPSHOT`).

* **Every push to `main`** (a merged PR or a direct commit) takes the highest existing build of the base, from the git tags,
  Maven Central and the Central snapshot repository, adds 1, builds, tests, publishes that version (e.g. `1.0.0.N-SNAPSHOT`)
  to the [Central snapshot repository](https://central.sonatype.com/repository/maven-snapshots/) and creates the tag `1.0.0.N`.
* Pushes run one after another (workflow concurrency queue), so two quick merges get two different numbers.
* PR builds, forks and runs without the deploy secrets build and test `1.0.0.0-SNAPSHOT` and never use up a number.
* **Release candidate or final release:** run the workflow by hand (Actions > Java CI Combined > Run workflow), choose the branch
  `main`, tick `deploy` and pick `RC`, `BETA`, `ALPHA` or `release` as qualifier. That publishes the current code once with the
  next build number (e.g. `1.0.0.N-RC` or `1.0.0.N`) to Maven Central and creates a GitHub release with the `.lex` files,
  without a commit; the pom keeps `-SNAPSHOT`.
* To start a new line change `extension.version.base`.
