package org.lucee.extension.http;

import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.URI;
import java.net.URISyntaxException;
import java.net.URL;
import java.nio.charset.Charset;
import java.nio.charset.StandardCharsets;
import java.security.GeneralSecurityException;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.Iterator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.concurrent.atomic.AtomicReference;

import javax.net.ssl.SSLContext;

import org.apache.hc.client5.http.HttpRoute;
import org.apache.hc.client5.http.auth.AuthSchemeFactory;
import org.apache.hc.client5.http.auth.AuthScope;
import org.apache.hc.client5.http.auth.StandardAuthScheme;
import org.apache.hc.client5.http.auth.UsernamePasswordCredentials;
import org.apache.hc.client5.http.classic.methods.HttpUriRequestBase;
import org.apache.hc.client5.http.config.ConnectionConfig;
import org.apache.hc.client5.http.config.RequestConfig;
import org.apache.hc.client5.http.cookie.BasicCookieStore;
import org.apache.hc.client5.http.cookie.StandardCookieSpec;
import org.apache.hc.client5.http.entity.UrlEncodedFormEntity;
import org.apache.hc.client5.http.entity.mime.AbstractContentBody;
import org.apache.hc.client5.http.entity.mime.FormBodyPartBuilder;
import org.apache.hc.client5.http.entity.mime.HttpMultipartMode;
import org.apache.hc.client5.http.entity.mime.MultipartEntityBuilder;
import org.apache.hc.client5.http.entity.mime.StringBody;
import org.apache.hc.client5.http.impl.auth.BasicAuthCache;
import org.apache.hc.client5.http.impl.auth.BasicCredentialsProvider;
import org.apache.hc.client5.http.impl.auth.BasicScheme;
import org.apache.hc.client5.http.impl.auth.BasicSchemeFactory;
import org.apache.hc.client5.http.impl.auth.DigestSchemeFactory;
import org.apache.hc.client5.http.impl.classic.CloseableHttpClient;
import org.apache.hc.client5.http.impl.classic.HttpClientBuilder;
import org.apache.hc.client5.http.impl.cookie.BasicClientCookie;
import org.apache.hc.client5.http.impl.io.PoolingHttpClientConnectionManager;
import org.apache.hc.client5.http.impl.io.PoolingHttpClientConnectionManagerBuilder;
import org.apache.hc.client5.http.protocol.HttpClientContext;
import org.apache.hc.client5.http.ssl.DefaultClientTlsStrategy;
import org.apache.hc.client5.http.ssl.HostnameVerificationPolicy;
import org.apache.hc.client5.http.ssl.NoopHostnameVerifier;
import org.apache.hc.core5.http.ClassicHttpResponse;
import org.apache.hc.core5.http.ContentType;
import org.apache.hc.core5.http.HttpEntity;
import org.apache.hc.core5.http.HttpHost;
import org.apache.hc.core5.http.HttpRequest;
import org.apache.hc.core5.http.HttpResponse;
import org.apache.hc.core5.http.Method;
import org.apache.hc.core5.http.NameValuePair;
import org.apache.hc.core5.http.NoHttpResponseException;
import org.apache.hc.core5.http.config.Lookup;
import org.apache.hc.core5.http.config.RegistryBuilder;
import org.apache.hc.core5.http.io.SocketConfig;
import org.apache.hc.core5.http.io.entity.AbstractHttpEntity;
import org.apache.hc.core5.http.io.entity.ByteArrayEntity;
import org.apache.hc.core5.http.io.entity.EntityUtils;
import org.apache.hc.core5.http.io.entity.InputStreamEntity;
import org.apache.hc.core5.http.io.entity.StringEntity;
import org.apache.hc.core5.http.message.BasicNameValuePair;
import org.apache.hc.core5.http.protocol.HttpContext;
import org.apache.hc.core5.io.CloseMode;
import org.apache.hc.core5.pool.PoolStats;
import org.apache.hc.core5.util.TimeValue;
import org.apache.hc.core5.util.Timeout;

import lucee.commons.io.res.Resource;
import lucee.commons.net.http.HTTPClientEngine;
import lucee.commons.net.http.HTTPRequest;
import lucee.commons.net.http.HTTPResponse;
import lucee.commons.net.http.Header;
import lucee.runtime.config.Config;
import lucee.runtime.exp.PageException;
import lucee.runtime.net.proxy.ProxyData;
import lucee.runtime.type.Struct;

/**
 * The full featured HTTP engine for Lucee, based on Apache HttpClient 5. It replaces the built-in
 * engine (java.net.http) of the Lucee core and does what the built-in engine rejects: NTLM, Digest and
 * the other authentication schemes of HttpClient, the headers the JDK client does not allow to set
 * (Host, Connection, Expect, Upgrade) and Basic authentication at a proxy for HTTPS (CONNECT).
 *
 * Redirects, credentials on redirects, the TLS settings and the proxy are handled like the built-in
 * engine does, so a request behaves the same with both engines.
 */
public final class HC5Engine implements HTTPClientEngine {

	private static final int POOL_MAX_CONN = 1000;
	private static final int POOL_MAX_CONN_PER_ROUTE = 100;
	private static final long POOL_CONN_TTL_MS = 15000;
	private static final long POOL_CONN_INACTIVITY_MS = 2000;
	// connection pools (one per TLS configuration) that are kept, the least recently used one is retired
	// when there are more
	private static final int MAX_POOLS = 64;
	// like the built-in engine
	private static final int MAX_REDIRECTS = 50;

	private static final List<String> FEATURES = Collections.unmodifiableList(Arrays.asList(FEATURE_NTLM, FEATURE_PREEMPTIVE_AUTH, FEATURE_RESTRICTED_HEADERS,
			FEATURE_TLS_OPTIONS, FEATURE_POOL));

	private static final List<String> SCHEMES_NTLM = Collections.singletonList(StandardAuthScheme.NTLM);
	private static final List<String> SCHEMES_DEFAULT = Collections.unmodifiableList(Arrays.asList(StandardAuthScheme.DIGEST, StandardAuthScheme.BASIC));

	@SuppressWarnings("deprecation")
	private static final Lookup<AuthSchemeFactory> AUTH_SCHEMES = RegistryBuilder.<AuthSchemeFactory>create().register(StandardAuthScheme.BASIC, BasicSchemeFactory.INSTANCE)
			.register(StandardAuthScheme.DIGEST, DigestSchemeFactory.INSTANCE)
			.register(StandardAuthScheme.NTLM, org.apache.hc.client5.http.impl.auth.NTLMSchemeFactory.INSTANCE).build();

	/**
	 * a connection pool and the client that uses it, the client has no state of a request (cookies,
	 * credentials, proxy, redirects and time-outs are set per request)
	 */
	private static final class Pool {
		final PoolingHttpClientConnectionManager manager;
		final CloseableHttpClient client;

		Pool(PoolingHttpClientConnectionManager manager, CloseableHttpClient client) {
			this.manager = manager;
			this.client = client;
		}
	}

	// all access to pools and retired is synchronized on lock
	private final Object lock = new Object();
	// key: hash of the TLS configuration (it contains passwords, so only the hash is kept), access order
	// for the LRU
	private final LinkedHashMap<String, Pool> pools = new LinkedHashMap<>(16, 0.75f, true);
	// pools that are no longer used for new requests, they are closed as soon as no connection is leased
	private final List<Pool> retired = new ArrayList<>();

	@Override
	public void init(Config config) throws PageException {
	}

	@Override
	public String getName() {
		return "httpclient5";
	}

	@Override
	public boolean supports(String feature) {
		return feature != null && FEATURES.contains(feature.trim().toLowerCase(Locale.ROOT));
	}

	// ------------------------------------------------------------------------------------------
	// pool and client
	// ------------------------------------------------------------------------------------------

	private Pool pool(HTTPRequest r) throws IOException {
		String key = poolKey(r);
		synchronized (lock) {
			Pool p = pools.get(key);
			if (p != null) return p;
			p = createPool(r, POOL_MAX_CONN, POOL_MAX_CONN_PER_ROUTE);
			pools.put(key, p);
			if (pools.size() > MAX_POOLS) {
				Iterator<Pool> it = pools.values().iterator();
				retired.add(it.next());
				it.remove();
				closeRetired();
			}
			return p;
		}
	}

	private static String poolKey(HTTPRequest r) throws IOException {
		StringBuilder sb = new StringBuilder();
		append(sb, r.getClientCert());
		append(sb, r.getClientCertPassword());
		append(sb, r.getTrustStore());
		append(sb, r.getTrustStorePassword());
		sb.append(r.isSslVerify());
		try {
			byte[] hash = MessageDigest.getInstance("SHA-256").digest(sb.toString().getBytes(StandardCharsets.UTF_8));
			StringBuilder hex = new StringBuilder();
			for (byte b: hash) {
				hex.append(Character.forDigit((b >> 4) & 0xF, 16)).append(Character.forDigit(b & 0xF, 16));
			}
			return hex.toString();
		}
		catch (NoSuchAlgorithmException e) {
			throw Util.engine().getExceptionUtil().toIOException(e);
		}
	}

	private static void append(StringBuilder sb, String value) {
		// with the length, so the values can not be shifted from one into the other
		if (value == null) sb.append("-1:");
		else sb.append(value.length()).append(':').append(value);
		sb.append('|');
	}

	private static Pool createPool(HTTPRequest r, int maxTotal, int maxPerRoute) throws IOException {
		// the same SSL context as the built-in engine: the trust store of the JVM, the custom cacerts of Lucee
		// (SSLCertificateInstall) and the trustStore of the request, or no verification at all
		SSLContext ctx;
		try {
			ctx = Util.engine().getHTTPUtil().createSSLContext(r.getClientCert(), r.getClientCertPassword(), r.getTrustStore(), r.getTrustStorePassword(), r.isSslVerify());
		}
		catch (GeneralSecurityException e) {
			throw Util.engine().getExceptionUtil().toIOException(e);
		}
		// with the built-in policy the JDK verifies the host name and a verifier is not asked, so for no verification the verifier decides
		DefaultClientTlsStrategy tls = r.isSslVerify() ? new DefaultClientTlsStrategy(ctx)
				: new DefaultClientTlsStrategy(ctx, HostnameVerificationPolicy.CLIENT, NoopHostnameVerifier.INSTANCE);

		PoolingHttpClientConnectionManager cm = PoolingHttpClientConnectionManagerBuilder.create().setTlsSocketStrategy(tls).setMaxConnTotal(maxTotal)
				.setMaxConnPerRoute(maxPerRoute).setDefaultSocketConfig(SocketConfig.custom().setTcpNoDelay(true).setSoReuseAddress(true).build())
				.setDefaultConnectionConfig(ConnectionConfig.custom().setTimeToLive(TimeValue.ofMilliseconds(POOL_CONN_TTL_MS))
						.setValidateAfterInactivity(TimeValue.ofMilliseconds(POOL_CONN_INACTIVITY_MS)).build())
				.build();

		// no thread of its own that evicts idle connections, the core calls closeIdleConnections() regularly.
		// The redirects are followed by the engine itself (see execute), like the built-in engine does.
		CloseableHttpClient client = HttpClientBuilder.create().setConnectionManager(cm).disableRedirectHandling().setRetryStrategy(new RetryStrategy())
				.setDefaultAuthSchemeRegistry(AUTH_SCHEMES).build();
		return new Pool(cm, client);
	}

	/**
	 * closes the retired pools that have no leased connection anymore, the other ones only close their
	 * idle connections, must be called with the lock
	 */
	private void closeRetired() {
		Iterator<Pool> it = retired.iterator();
		while (it.hasNext()) {
			Pool p = it.next();
			p.manager.closeIdle(TimeValue.ZERO_MILLISECONDS);
			PoolStats stats = p.manager.getTotalStats();
			if (stats.getLeased() == 0 && stats.getPending() == 0) {
				p.manager.close(CloseMode.GRACEFUL);
				it.remove();
			}
		}
	}

	// ------------------------------------------------------------------------------------------
	// request
	// ------------------------------------------------------------------------------------------

	@Override
	public HTTPResponse execute(HTTPRequest r) throws IOException {
		// the entry in the debugging output (LDEV-2822), only when debugging is enabled for the request
		HC5Debug debug = HC5Debug.begin();
		if (debug == null) return execute(r, null);
		HTTPResponse response = null;
		Throwable failure = null;
		try {
			response = execute(r, debug);
			return response;
		}
		catch (IOException | RuntimeException e) {
			failure = e;
			throw e;
		}
		finally {
			debug.end(response, failure);
		}
	}

	private HTTPResponse execute(HTTPRequest r, HC5Debug debug) throws IOException {
		r.validate();
		URL url = r.getURL();
		URI uri = toURI(url);
		if (debug != null) debug.target(r.getMethod(), url);

		String redirect = r.getRedirect() == null ? "true" : r.getRedirect().trim();
		boolean follow = !"false".equalsIgnoreCase(redirect);
		// like the built-in engine: without pooling Apache HttpClient always followed redirects the lax way
		// (LaxRedirectStrategy), that stays (LDEV-6675)
		boolean lax = "lax".equalsIgnoreCase(redirect) || (follow && !r.isPooling());

		RequestConfig.Builder rc = RequestConfig.custom().setCookieSpec(StandardCookieSpec.RELAXED).setRedirectsEnabled(false);
		if (r.getConnectTimeout() >= 0) rc.setConnectTimeout(Timeout.ofMilliseconds(r.getConnectTimeout()));
		if (r.getConnectionRequestTimeout() >= 0) rc.setConnectionRequestTimeout(Timeout.ofMilliseconds(r.getConnectionRequestTimeout()));
		if (r.getReadTimeout() >= 0) rc.setResponseTimeout(Timeout.ofMilliseconds(r.getReadTimeout()));

		HttpClientContext context = HttpClientContext.create();

		// cookies of the request, without a domain they are for the host of the URL (a cookie without a
		// domain is never sent by HttpClient)
		BasicCookieStore cookieStore = new BasicCookieStore();
		Charset cs = Util.toCharset(r.getCharset(), StandardCharsets.UTF_8);
		for (HTTPRequest.Cookie c: r.getCookies()) {
			BasicClientCookie cookie = new BasicClientCookie(encode(c.getName(), cs), encode(c.getValue(), cs));
			cookie.setDomain(Util.isEmpty(c.getDomain(), true) ? url.getHost() : c.getDomain().trim());
			cookie.setPath(Util.isEmpty(c.getPath(), true) ? "/" : c.getPath().trim());
			cookieStore.addCookie(cookie);
		}
		context.setCookieStore(cookieStore);

		// credentials, only for the host of the URL, a redirect to another host does not get them (like
		// the built-in engine)
		BasicCredentialsProvider credsProvider = new BasicCredentialsProvider();
		boolean ntlm = false;
		if (!Util.isEmpty(r.getUsername(), true)) {
			char[] pw = (r.getPassword() == null ? "" : r.getPassword()).toCharArray();
			AuthScope scope = new AuthScope(url.getHost(), -1);
			if (r.getAuthType() == HTTPRequest.AUTH_NTLM) {
				ntlm = true;
				credsProvider.setCredentials(scope, ntCredentials(r, pw));
			}
			else {
				UsernamePasswordCredentials creds = new UsernamePasswordCredentials(r.getUsername(), pw);
				credsProvider.setCredentials(scope, creds);
				if (r.isPreAuth()) {
					BasicScheme scheme = new BasicScheme();
					scheme.initPreemptive(creds);
					BasicAuthCache authCache = new BasicAuthCache();
					authCache.put(new HttpHost(uri.getScheme(), uri.getHost(), uri.getPort()), scheme);
					context.setAuthCache(authCache);
				}
			}
		}
		rc.setTargetPreferredAuthSchemes(ntlm ? SCHEMES_NTLM : SCHEMES_DEFAULT);
		rc.setProxyPreferredAuthSchemes(SCHEMES_DEFAULT);

		// proxy, without a proxy of the request there is none (no proxy system properties), like the built-in
		// engine. The port is resolved once, so the proxy and the scope of its credentials match.
		ProxyData proxy = r.getProxy();
		if (proxy != null && !Util.isEmpty(proxy.getServer(), true)) {
			String proxyServer = proxy.getServer().trim();
			int proxyPort = proxy.getPort() <= 0 ? 80 : proxy.getPort();
			rc.setProxy(new HttpHost(proxyServer, proxyPort));
			if (!Util.isEmpty(proxy.getUsername(), true)) {
				// for HTTPS HttpClient sends the credentials with the CONNECT of the tunnel after the proxy asked for them (407)
				credsProvider.setCredentials(new AuthScope(proxyServer, proxyPort),
						new UsernamePasswordCredentials(proxy.getUsername(), (proxy.getPassword() == null ? "" : proxy.getPassword()).toCharArray()));
			}
		}
		context.setCredentialsProvider(credsProvider);
		context.setRequestConfig(rc.build());

		// a pooled request uses the client of its pool, a request without pooling gets a client and a
		// connection of its own, they are closed with the response
		CloseableHttpClient client;
		CloseableHttpClient ownClient = null;
		if (r.isPooling()) {
			client = pool(r).client;
		}
		else {
			client = ownClient = createPool(r, 1, 1).client;
		}

		String method = r.getMethod();
		HttpEntity entity = createEntity(r, method);
		List<URI> locations = new ArrayList<>();
		AtomicReference<HttpUriRequestBase> current = new AtomicReference<>();
		r.setAbortHandler(() -> {
			HttpUriRequestBase req = current.get();
			if (req != null) req.cancel();
		});

		try {
			int redirects = 0;
			while (true) {
				HttpUriRequestBase req = createRequest(r, method, uri, entity);
				current.set(req);
				if (r.isAborted()) req.cancel();

				ClassicHttpResponse rsp;
				try {
					rsp = client.executeOpen(null, req, context);
				}
				catch (org.apache.hc.client5.http.ConnectTimeoutException e) {
					// a connect time-out is a connection failure, not a time-out of the request (408), like with the
					// built-in engine, so it must not be a SocketTimeoutException
					java.net.ConnectException ce = new java.net.ConnectException(e.getMessage());
					ce.initCause(e);
					throw ce;
				}
				if (debug != null) debug.exchange(context);
				int status = rsp.getCode();
				org.apache.hc.core5.http.Header loc = rsp.getFirstHeader("Location");
				String location = loc == null ? null : loc.getValue();

				if (follow && location != null && isRedirect(status) && mayFollow(status, method, lax)) {
					// read the rest of the response, so the connection can be used again
					try {
						EntityUtils.consume(rsp.getEntity());
					}
					finally {
						rsp.close();
					}
					if (++redirects > MAX_REDIRECTS) throw new IOException("Maximum redirects (" + MAX_REDIRECTS + ") exceeded");
					URI next = resolve(uri, location);
					locations.add(next);
					// 301, 302 and 303 turn the request into a GET without a body, 307 and 308 keep the method and the body
					if (status == 301 || status == 302 || status == 303) {
						if (!"HEAD".equals(method) && !"GET".equals(method)) {
							method = "GET";
							entity = null;
						}
					}
					else if (entity != null && !entity.isRepeatable()) {
						throw new IOException("the redirect [" + status + "] to [" + next + "] needs the body of the request a second time, but the body is a stream that can only be read once");
					}
					uri = next;
					continue;
				}
				try {
					return new HC5Response(rsp, ownClient, url, uri, locations);
				}
				catch (IOException | RuntimeException e) {
					rsp.close();
					throw e;
				}
			}
		}
		catch (IOException | RuntimeException e) {
			if (ownClient != null) ownClient.close();
			throw e;
		}
	}

	@SuppressWarnings("deprecation")
	private static org.apache.hc.client5.http.auth.Credentials ntCredentials(HTTPRequest r, char[] pw) {
		return new org.apache.hc.client5.http.auth.NTCredentials(r.getUsername(), pw, r.getWorkStation(), r.getDomain());
	}

	private static boolean isRedirect(int status) {
		return status == 301 || status == 302 || status == 303 || status == 307 || status == 308;
	}

	// like the built-in engine and the redirect strategies of Apache HttpClient: a 303 always, otherwise GET and
	// HEAD, lax also POST and DELETE
	private static boolean mayFollow(int status, String method, boolean lax) {
		if (status == 303) return true;
		if ("GET".equals(method) || "HEAD".equals(method)) return true;
		return lax && ("POST".equals(method) || "DELETE".equals(method));
	}

	private static URI toURI(URL url) throws IOException {
		try {
			return url.toURI();
		}
		catch (URISyntaxException e) {
			try {
				return URI.create(url.toExternalForm());
			}
			catch (IllegalArgumentException iae) {
				throw new IOException("invalid URL [" + url + "]: " + e.getMessage(), e);
			}
		}
	}

	private static URI resolve(URI base, String location) throws IOException {
		URI next;
		try {
			next = base.resolve(location.trim());
		}
		catch (IllegalArgumentException e) {
			throw new IOException("invalid redirect location [" + location + "]: " + e.getMessage(), e);
		}
		if (next.getHost() == null || !("http".equalsIgnoreCase(next.getScheme()) || "https".equalsIgnoreCase(next.getScheme()))) {
			throw new IOException("invalid redirect location [" + location + "]");
		}
		return next;
	}

	private static String encode(String str, Charset charset) {
		if (str == null) return "";
		if (needsEncoding(str)) return java.net.URLEncoder.encode(str, charset);
		return str;
	}

	private static boolean needsEncoding(String str) {
		for (int i = 0; i < str.length(); i++) {
			char c = str.charAt(i);
			if (c < 33 || c > 126 || c == ';' || c == ',' || c == '=' || c == '"' || c == '\\') return true;
		}
		return false;
	}

	private static HttpUriRequestBase createRequest(HTTPRequest r, String method, URI uri, HttpEntity entity) {
		HttpUriRequestBase req = new HttpUriRequestBase(method, uri);
		for (Header h: r.getHeaders()) {
			// the length comes from the body, HttpClient fails when the header is already set
			if ("content-length".equalsIgnoreCase(h.getName())) continue;
			// Host, Connection, Expect and Upgrade are sent like they are set, HttpClient only sets them when they are missing
			req.addHeader(h.getName(), h.getValue());
		}
		if (entity != null) req.setEntity(entity);
		return req;
	}

	private static HttpEntity createEntity(HTTPRequest r, String method) throws IOException {
		boolean hasBody = r.getBody() != null || r.getFormFields() != null || r.getParts() != null;
		if (!hasBody) return null;
		if (HTTPRequest.HEAD.equals(method) || HTTPRequest.TRACE.equals(method) || HTTPRequest.OPTIONS.equals(method)) {
			throw new IOException("the method [" + method.toLowerCase(Locale.ROOT) + "] does not support a body");
		}
		String charset = r.getCharset();

		// multipart
		if (r.getParts() != null) {
			// no charset parameter in the content type, like HttpClient 4 did
			MultipartEntityBuilder mpe = MultipartEntityBuilder.create().setMode(HttpMultipartMode.STRICT).setContentType(ContentType.create("multipart/form-data"));
			for (HTTPRequest.Part part: r.getParts()) {
				if (part.getResource() != null) {
					mpe.addPart(FormBodyPartBuilder.create(part.getName(), new ResourceBody(part.getResource(), part.getMimeType())).build());
				}
				else {
					Charset cs = Util.toCharset(Util.isEmpty(part.getCharset(), true) ? charset : part.getCharset(), Util.webCharset());
					mpe.addPart(FormBodyPartBuilder.create(part.getName(), new StringBody(part.getValue() == null ? "" : part.getValue(), ContentType.TEXT_PLAIN.withCharset(cs)))
							.build());
				}
			}
			return mpe.build();
		}

		// form fields
		if (r.getFormFields() != null) {
			List<NameValuePair> list = new ArrayList<>();
			for (String[] field: r.getFormFields()) {
				list.add(new BasicNameValuePair(field[0], field[1]));
			}
			return new UrlEncodedFormEntity(list, Util.toCharset(charset, Util.webCharset()));
		}

		// raw body
		return rawEntity(r.getBody(), r.getBodyMimeType(), r.getBodyCharset());
	}

	private static HttpEntity rawEntity(Object value, String mimetype, String charset) throws IOException {
		ContentType ct = null;
		if (!Util.isEmpty(mimetype, true)) {
			ct = ContentType.create(mimetype.trim());
			if (!Util.isEmpty(charset, true)) ct = ct.withCharset(charset.trim());
		}

		try {
			if (value instanceof HttpEntity) return (HttpEntity) value;
			// streams are sent as they are read, they are not loaded into the memory first
			if (value instanceof InputStream) return new InputStreamEntity((InputStream) value, -1, ct);
			if (value instanceof Resource) return new ResourceEntity((Resource) value, ct);
			HttpEntity temp = temporaryStreamEntity(value, ct);
			if (temp != null) return temp;
			if (Util.engine().getDecisionUtil().isCastableToBinary(value, false)) return new ByteArrayEntity(Util.cast().toBinary(value), ct);

			boolean wasNull = false;
			if (ct == null) {
				wasNull = true;
				ct = ContentType.APPLICATION_OCTET_STREAM;
			}
			String str = Util.cast().toString(value);
			if ("<empty>".equals(str)) return new ByteArrayEntity(new byte[0], ct);
			if (wasNull && !Util.isEmpty(charset, true)) return new StringEntity(str, Charset.forName(charset.trim()));
			return new StringEntity(str, ct);
		}
		catch (IOException e) {
			throw e;
		}
		catch (Exception e) {
			throw Util.engine().getExceptionUtil().toIOException(e);
		}
	}

	/**
	 * the TemporaryStream of the core (a body the caller has written, in memory or in a file), it is not
	 * part of the loader, so it is recognized by its class name. The stream is sent as it is read, with
	 * its length.
	 */
	private static HttpEntity temporaryStreamEntity(Object value, ContentType ct) throws IOException {
		if (!"lucee.commons.io.TemporaryStream".equals(value.getClass().getName())) return null;
		try {
			InputStream is = (InputStream) value.getClass().getMethod("getInputStream").invoke(value);
			long length = ((Number) value.getClass().getMethod("length").invoke(value)).longValue();
			return new InputStreamEntity(is, length, ct);
		}
		catch (java.lang.reflect.InvocationTargetException e) {
			Throwable t = e.getCause();
			if (t instanceof IOException) throw (IOException) t;
			throw Util.engine().getExceptionUtil().toIOException(t);
		}
		catch (ReflectiveOperationException e) {
			throw Util.engine().getExceptionUtil().toIOException(e);
		}
	}

	/**
	 * a resource as body, sent as it is read, with its length, it can be sent again (redirect 307/308)
	 */
	private static final class ResourceEntity extends AbstractHttpEntity {
		private final Resource res;

		ResourceEntity(Resource res, ContentType ct) {
			super(ct, null);
			this.res = res;
		}

		@Override
		public boolean isRepeatable() {
			return true;
		}

		@Override
		public long getContentLength() {
			return res.length();
		}

		@Override
		public InputStream getContent() throws IOException {
			return res.getInputStream();
		}

		@Override
		public boolean isStreaming() {
			return false;
		}

		@Override
		public void close() {
		}
	}

	/**
	 * a file part of a multipart body, with the length of the file
	 */
	private static final class ResourceBody extends AbstractContentBody {

		private final Resource res;

		ResourceBody(Resource res, String mimetype) {
			super(Util.isEmpty(mimetype, true) ? ContentType.APPLICATION_OCTET_STREAM : ContentType.parse(mimetype));
			this.res = res;
		}

		@Override
		public String getFilename() {
			return res.getName();
		}

		@Override
		public void writeTo(OutputStream out) throws IOException {
			try (InputStream is = res.getInputStream()) {
				is.transferTo(out);
			}
		}

		@Override
		public long getContentLength() {
			return res.length();
		}
	}

	// ------------------------------------------------------------------------------------------
	// strategies
	// ------------------------------------------------------------------------------------------

	/**
	 * a pooled connection that the server closed in the meantime is a transient condition, an idempotent
	 * request (GET, HEAD, PUT, DELETE, OPTIONS, TRACE) is sent again, a POST or PATCH never (the server could
	 * have processed it). A status code is never a reason to send the request again.
	 */
	private static final class RetryStrategy implements org.apache.hc.client5.http.HttpRequestRetryStrategy {
		@Override
		public boolean retryRequest(HttpRequest request, IOException exception, int execCount, HttpContext context) {
			return execCount <= 2 && exception instanceof NoHttpResponseException && Method.isIdempotent(request.getMethod());
		}

		@Override
		public boolean retryRequest(HttpResponse response, int execCount, HttpContext context) {
			return false;
		}

		@Override
		public TimeValue getRetryInterval(HttpResponse response, int execCount, HttpContext context) {
			return TimeValue.ZERO_MILLISECONDS;
		}
	}

	// ------------------------------------------------------------------------------------------
	// maintenance
	// ------------------------------------------------------------------------------------------

	/**
	 * the core calls it after the trusted certificates changed (SSLCertificateInstall, SSLCertificateRemove,
	 * Administrator), the next requests get new pools with a new SSL context, requests that are still
	 * running complete on the old ones
	 */
	@Override
	public void releaseConnections() {
		synchronized (lock) {
			retired.addAll(pools.values());
			pools.clear();
			closeRetired();
		}
	}

	@Override
	public void closeIdleConnections() {
		synchronized (lock) {
			for (Pool p: pools.values()) {
				p.manager.closeExpired();
				p.manager.closeIdle(TimeValue.ofMilliseconds(POOL_CONN_TTL_MS));
			}
			closeRetired();
		}
	}

	@Override
	public void close() {
		synchronized (lock) {
			retired.addAll(pools.values());
			pools.clear();
			for (Pool p: retired) {
				p.manager.close(CloseMode.GRACEFUL);
			}
			retired.clear();
		}
	}

	@Override
	public Struct getMetaData() throws IOException {
		Struct sct = Util.engine().getCreationUtil().createStruct();
		sct.setEL("engine", getName());
		Struct pool = getPoolStats();
		sct.setEL("status", pool);
		Struct config = Util.engine().getCreationUtil().createStruct();
		config.setEL("defaultMaxPerRoute", POOL_MAX_CONN_PER_ROUTE);
		config.setEL("maxTotal", POOL_MAX_CONN);
		config.setEL("validateAfterInactivity", POOL_CONN_INACTIVITY_MS);
		config.setEL("maxPools", MAX_POOLS);
		sct.setEL("config", config);
		synchronized (lock) {
			sct.setEL("pools", pools.size());
			sct.setEL("retiredPools", retired.size());
		}
		return sct;
	}

	@Override
	public Struct getPoolStats() {
		List<PoolingHttpClientConnectionManager> managers = new ArrayList<>();
		synchronized (lock) {
			for (Pool p: pools.values()) {
				managers.add(p.manager);
			}
			for (Pool p: retired) {
				managers.add(p.manager);
			}
		}
		Struct sct = Util.engine().getCreationUtil().createStruct();
		Struct routes = Util.engine().getCreationUtil().createStruct();
		int leased = 0, available = 0, pending = 0, max = 0;
		for (PoolingHttpClientConnectionManager cm: managers) {
			PoolStats totals = cm.getTotalStats();
			leased += totals.getLeased();
			available += totals.getAvailable();
			pending += totals.getPending();
			max += totals.getMax();

			for (HttpRoute route: cm.getRoutes()) {
				PoolStats stats = cm.getStats(route);
				if ((stats.getLeased() + stats.getAvailable() + stats.getPending()) == 0) continue;
				Struct hc = Util.engine().getCreationUtil().createStruct();
				hc.setEL("leased", stats.getLeased());
				hc.setEL("available", stats.getAvailable());
				hc.setEL("pending", stats.getPending());
				hc.setEL("max", stats.getMax());
				hc.setEL("route", route.getTargetHost().toHostString());
				routes.setEL(route.getTargetHost().toHostString(), hc);
			}
		}
		sct.setEL("leased", leased);
		sct.setEL("available", available);
		sct.setEL("pending", pending);
		sct.setEL("max", max);
		sct.setEL("routes", routes);
		return sct;
	}
}
