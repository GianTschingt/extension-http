# Changelog

## 1.0.0.1-BETA

- [LDEV-2822](https://luceeserver.atlassian.net/browse/LDEV-2822) — with debugging enabled every HTTP call has an entry in the section "HTTP" of the debugging output: method, host and path (never the query string or the user info), status code, duration and whether the pooled connection was reused. The entries are added with the generic data of the debugger of Lucee (the same as `DebugAdd()`), there is no entry without debugging. Tests in `tests/HttpDebugTest.cfc`
- [LDEV-2542](https://luceeserver.atlassian.net/browse/LDEV-2542) — the result of `cfhttp` has the key `request` with the request that was sent, as with the built-in engine. Lucee builds the key and masks sensitive values, the extension supplies the final URL after the redirects, tests in `tests/HttpRequestKeyTest.cfc` check the key against what the engine sent (they are skipped on a Lucee version without the key)
- [LDEV-2675](https://luceeserver.atlassian.net/browse/LDEV-2675) — the result of `cfhttp` has the key `connection`: if the connection of the response was taken from the pool (`reused`), the number of requests it has carried (`requests`) and the stats of the pool for the route (`leased`, `available`, `pending`, `max`). A request with `pooling=false` has `pooled=false` and no pool stats. The extension detects the reuse from the number of requests of the connection and supplies the data with `getConnectionInfo()` of its response, Lucee adds the key. Tests in `tests/HttpConnectionTest.cfc` compare the key with the connections a server has accepted (they need a Lucee version that has LDEV-2675)
- [LDEV-3779](https://luceeserver.atlassian.net/browse/LDEV-3779) — tests for the listener of `cfhttp` (`before`, `after`, `error`, as tag attribute `listener`, `this.http.listener` or `httpListener` of `cfapplication`) with this engine. The listener is part of the tag in Lucee and works with every engine, the extension needs no change; the tests check that what a listener changes in the request is what this engine sends and that what this engine answers is what the listener gets. It needs a Lucee version that has LDEV-3779.

## 1.0.0.0-BETA

- [LDEV-6677](https://luceeserver.atlassian.net/browse/LDEV-6677) — first BETA, published to Maven Central and as a GitHub pre-release with the .lex files, tested with the Lucee 9 versions from `LUCEE_TEST_VERSIONS_9`

## 1.0.0.0-ALPHA

- [LDEV-6677](https://luceeserver.atlassian.net/browse/LDEV-6677) — initial version, the HTTP engine based on Apache HttpClient 5, registered with the manifest attribute `http-engine`
- requires Lucee 9.0.0.279-ALPHA or newer, NTLM, Digest and proxy tunnel authentication, the restricted headers, redirects, cookies, retries and the connection pools work as described in the README
- the extension is licensed under the LGPL 2.1, like Lucee
