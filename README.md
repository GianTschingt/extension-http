# Lucee HTTP Extension

With Lucee 9, Apache HttpClient moved out of the core. The core sends HTTP requests (the tag `cfhttp`, downloads of extensions, the AI engines) with a built-in engine based on `java.net.http`. This extension replaces it with an engine based on Apache HttpClient 5.

Install it when you need what the built-in engine can not do:

* NTLM authentication (`authType="NTLM"` with `domain` and `workstation`)
* setting the headers the JDK does not allow to set (`Host`, `Connection`, `Content-Length`, `Expect`, `Upgrade`)
* the connection pool and its statistics (`getSystemInfo()`)
* all the behaviour of the engine of Lucee 8 (separate connect and socket timeouts, redirect handling, retry of a pooled connection the server closed)

Without the extension, a request that needs one of these fails with a message that names this extension.

Differences to Lucee 8: Apache HttpClient 5 sends no `Content-Transfer-Encoding` header for the parts of a multipart request (RFC 7578 says to omit it), and some error messages differ.

Issues: https://luceeserver.atlassian.net/browse/LDEV-6677
