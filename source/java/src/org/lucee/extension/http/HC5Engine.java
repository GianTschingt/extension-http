package org.lucee.extension.http;

import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.URI;
import java.net.URL;
import java.nio.charset.Charset;
import java.security.GeneralSecurityException;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

import javax.net.ssl.SSLContext;

import org.apache.hc.client5.http.HttpRoute;
import org.apache.hc.client5.http.auth.AuthScope;
import org.apache.hc.client5.http.auth.NTCredentials;
import org.apache.hc.client5.http.auth.UsernamePasswordCredentials;
import org.apache.hc.client5.http.classic.methods.HttpUriRequestBase;
import org.apache.hc.client5.http.config.ConnectionConfig;
import org.apache.hc.client5.http.config.RequestConfig;
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
import org.apache.hc.client5.http.impl.classic.CloseableHttpClient;
import org.apache.hc.core5.http.ClassicHttpResponse;
import org.apache.hc.client5.http.impl.classic.HttpClientBuilder;
import org.apache.hc.client5.http.impl.cookie.BasicClientCookie;
import org.apache.hc.client5.http.cookie.BasicCookieStore;
import org.apache.hc.client5.http.impl.io.PoolingHttpClientConnectionManager;
import org.apache.hc.client5.http.impl.io.PoolingHttpClientConnectionManagerBuilder;
import org.apache.hc.client5.http.protocol.HttpClientContext;
import org.apache.hc.client5.http.protocol.RedirectLocations;
import org.apache.hc.client5.http.ssl.DefaultClientTlsStrategy;
import org.apache.hc.client5.http.ssl.NoopHostnameVerifier;
import org.apache.hc.client5.http.ssl.TrustAllStrategy;
import org.apache.hc.core5.http.ContentType;
import org.apache.hc.core5.http.HttpEntity;
import org.apache.hc.core5.http.HttpHost;
import org.apache.hc.core5.http.HttpRequest;
import org.apache.hc.core5.http.HttpResponse;
import org.apache.hc.core5.http.NameValuePair;
import org.apache.hc.core5.http.NoHttpResponseException;
import org.apache.hc.core5.http.io.SocketConfig;
import org.apache.hc.core5.http.io.entity.ByteArrayEntity;
import org.apache.hc.core5.http.io.entity.StringEntity;
import org.apache.hc.core5.http.message.BasicNameValuePair;
import org.apache.hc.core5.http.protocol.HttpContext;
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
 * engine (java.net.http) of the Lucee core.
 */
public final class HC5Engine implements HTTPClientEngine {

	private static final int POOL_MAX_CONN = 1000;
	private static final int POOL_MAX_CONN_PER_ROUTE = 100;
	private static final long POOL_CONN_TTL_MS = 15000;
	private static final long POOL_CONN_INACTIVITY_MS = 2000;

	// one connection manager (pool) per TLS configuration
	private final Map<String, PoolingHttpClientConnectionManager> managers = new ConcurrentHashMap<>();
	private volatile CloseableHttpClient sharedClient;
	private volatile PoolingHttpClientConnectionManager sharedManager;

	@Override
	public void init(Config config) throws PageException {
	}

	@Override
	public String getName() {
		return "httpclient5";
	}

	@Override
	public boolean supports(String feature) {
		return true;
	}

	// ------------------------------------------------------------------------------------------
	// pool and client
	// ------------------------------------------------------------------------------------------

	private PoolingHttpClientConnectionManager manager(HTTPRequest r, boolean pooled) throws IOException {
		String key = r.getClientCert() + ":" + r.getClientCertPassword() + ":" + r.getTrustStore() + ":" + r.getTrustStorePassword() + ":" + r.isSslVerify();
		if (pooled) {
			PoolingHttpClientConnectionManager cm = managers.get(key);
			if (cm == null) {
				synchronized (managers) {
					cm = managers.get(key);
					if (cm == null) {
						cm = createManager(r, POOL_MAX_CONN, POOL_MAX_CONN_PER_ROUTE);
						managers.put(key, cm);
					}
				}
			}
			return cm;
		}
		// not pooled: a connection manager for this request only
		return createManager(r, 1, 1);
	}

	private PoolingHttpClientConnectionManager createManager(HTTPRequest r, int maxTotal, int maxPerRoute) throws IOException {
		SSLContext ctx;
		try {
			ctx = Util.engine().getHTTPUtil().createSSLContext(r.getClientCert(), r.getClientCertPassword(), r.getTrustStore(), r.getTrustStorePassword(), r.isSslVerify());
		}
		catch (GeneralSecurityException e) {
			throw Util.engine().getExceptionUtil().toIOException(e);
		}
		// with the built-in policy the JDK verifies the host name and a verifier is not asked, so for no verification the verifier decides
		DefaultClientTlsStrategy tls = r.isSslVerify() ? new DefaultClientTlsStrategy(ctx)
				: new DefaultClientTlsStrategy(ctx, org.apache.hc.client5.http.ssl.HostnameVerificationPolicy.CLIENT, NoopHostnameVerifier.INSTANCE);

		return PoolingHttpClientConnectionManagerBuilder.create().setTlsSocketStrategy(tls).setMaxConnTotal(maxTotal).setMaxConnPerRoute(maxPerRoute)
				.setDefaultSocketConfig(SocketConfig.custom().setTcpNoDelay(true).setSoReuseAddress(true).build())
				.setDefaultConnectionConfig(ConnectionConfig.custom().setTimeToLive(TimeValue.ofMilliseconds(POOL_CONN_TTL_MS))
						.setValidateAfterInactivity(TimeValue.ofMilliseconds(POOL_CONN_INACTIVITY_MS)).build())
				.build();
	}

	private HttpClientBuilder builder(PoolingHttpClientConnectionManager cm, boolean shared, String redirect) {
		HttpClientBuilder b = HttpClientBuilder.create().setConnectionManager(cm).setConnectionManagerShared(shared).setRetryStrategy(new RetryStrategy());
		if (shared) b.evictIdleConnections(TimeValue.ofSeconds(30)).evictExpiredConnections();

		boolean lax = "lax".equalsIgnoreCase(redirect);
		b.setRedirectStrategy(new RedirectStrategy(lax));
		return b;
	}

	private CloseableHttpClient sharedClient() throws IOException {
		CloseableHttpClient c = sharedClient;
		if (c == null) {
			synchronized (managers) {
				c = sharedClient;
				if (c == null) {
					HTTPRequest def = new HTTPRequest();
					sharedManager = manager(def, true);
					sharedClient = c = builder(sharedManager, true, "true").build();
				}
			}
		}
		return c;
	}

	// ------------------------------------------------------------------------------------------
	// request
	// ------------------------------------------------------------------------------------------

	@Override
	public HTTPResponse execute(HTTPRequest r) throws IOException {
		r.validate();
		URL url = r.getURL();
		HttpUriRequestBase req = createRequest(r);

		boolean redirectEnabled = Util.toBooleanValue(r.getRedirect(), true);
		RequestConfig.Builder rc = RequestConfig.custom().setCookieSpec(StandardCookieSpec.RELAXED).setRedirectsEnabled(redirectEnabled);
		if (r.getConnectTimeout() >= 0) rc.setConnectTimeout(Timeout.ofMilliseconds(r.getConnectTimeout()));
		if (r.getConnectionRequestTimeout() >= 0) rc.setConnectionRequestTimeout(Timeout.ofMilliseconds(r.getConnectionRequestTimeout()));
		if (r.getReadTimeout() >= 0) rc.setResponseTimeout(Timeout.ofMilliseconds(r.getReadTimeout()));

		ProxyData proxy = r.getProxy();
		boolean hasProxy = proxy != null && !Util.isEmpty(proxy.getServer(), true);
		HttpHost target = new HttpHost(url.getProtocol(), url.getHost(), url.getPort());

		boolean tls = !Util.isEmpty(r.getClientCert(), true) || !Util.isEmpty(r.getTrustStore(), true) || !r.isSslVerify();
		boolean ntlm = !Util.isEmpty(r.getUsername(), true) && r.getAuthType() == HTTPRequest.AUTH_NTLM;
		boolean dedicated = !r.isPooling() || tls || ntlm || !r.getCookies().isEmpty() || "lax".equalsIgnoreCase(r.getRedirect());

		HttpClientContext context = HttpClientContext.create();
		BasicCookieStore cookieStore = new BasicCookieStore();
		String cs = Util.isEmpty(r.getCharset(), true) ? "UTF-8" : r.getCharset();
		for (HTTPRequest.Cookie c: r.getCookies()) {
			BasicClientCookie cookie = new BasicClientCookie(encode(c.getName(), cs), encode(c.getValue(), cs));
			if (!Util.isEmpty(c.getDomain(), true)) cookie.setDomain(c.getDomain());
			if (!Util.isEmpty(c.getPath(), true)) cookie.setPath(c.getPath());
			cookieStore.addCookie(cookie);
		}
		context.setCookieStore(cookieStore);

		BasicCredentialsProvider credsProvider = null;
		if (!Util.isEmpty(r.getUsername(), true)) {
			credsProvider = new BasicCredentialsProvider();
			char[] pw = (r.getPassword() == null ? "" : r.getPassword()).toCharArray();
			if (ntlm) {
				credsProvider.setCredentials(new AuthScope(null, -1), new NTCredentials(r.getUsername(), pw, r.getWorkStation(), r.getDomain()));
			}
			else {
				UsernamePasswordCredentials creds = new UsernamePasswordCredentials(r.getUsername(), pw);
				credsProvider.setCredentials(new AuthScope(null, -1), creds);
				if (r.isPreAuth()) {
					BasicScheme scheme = new BasicScheme();
					scheme.initPreemptive(creds);
					BasicAuthCache authCache = new BasicAuthCache();
					authCache.put(target, scheme);
					context.setAuthCache(authCache);
				}
			}
		}
		if (hasProxy) {
			rc.setProxy(new HttpHost(proxy.getServer(), proxy.getPort() == -1 ? 80 : proxy.getPort()));
			if (!Util.isEmpty(proxy.getUsername())) {
				if (credsProvider == null) credsProvider = new BasicCredentialsProvider();
				credsProvider.setCredentials(new AuthScope(proxy.getServer(), proxy.getPort()),
						new UsernamePasswordCredentials(proxy.getUsername(), (proxy.getPassword() == null ? "" : proxy.getPassword()).toCharArray()));
			}
		}
		if (credsProvider != null) context.setCredentialsProvider(credsProvider);
		req.setConfig(rc.build());

		CloseableHttpClient client;
		boolean closeClient;
		if (dedicated) {
			PoolingHttpClientConnectionManager cm = manager(r, r.isPooling());
			// the pool of a pooled manager is shared, closing the client does not close it
			client = builder(cm, r.isPooling(), r.getRedirect()).build();
			closeClient = true;
		}
		else {
			client = sharedClient();
			closeClient = false;
		}

		r.setAbortHandler(req::cancel);
		try {
			ClassicHttpResponse rsp = client.executeOpen(null, req, context);
			RedirectLocations rl = context.getRedirectLocations();
			URI last = req.getUri();
			return new HC5Response(rsp, closeClient ? client : null, url, last, rl == null ? null : rl.getAll());
		}
		catch (org.apache.hc.client5.http.ConnectTimeoutException e) {
			if (closeClient) client.close();
			// the tag reports a SocketTimeoutException as a request time-out, a connect time-out is a connection failure (HttpClient 4 had a different type)
			java.io.InterruptedIOException ioe = new java.io.InterruptedIOException(e.getMessage());
			ioe.initCause(e);
			throw ioe;
		}
		catch (IOException | RuntimeException e) {
			if (closeClient) client.close();
			throw e;
		}
		catch (Exception e) {
			if (closeClient) client.close();
			throw Util.engine().getExceptionUtil().toIOException(e);
		}
	}

	private static String encode(String str, String charset) {
		if (str == null) return "";
		try {
			if (needsEncoding(str)) return java.net.URLEncoder.encode(str, charset);
		}
		catch (Exception e) {
		}
		return str;
	}

	private static boolean needsEncoding(String str) {
		for (int i = 0; i < str.length(); i++) {
			char c = str.charAt(i);
			if (c < 33 || c > 126 || c == ';' || c == ',' || c == '=' || c == '"' || c == '\\') return true;
		}
		return false;
	}

	private static HttpUriRequestBase createRequest(HTTPRequest r) throws IOException {
		String method = r.getMethod();
		// the methods the tag knows are sent with their name, the other ones as POST
		String m = HTTPRequest.GET.equals(method) || HTTPRequest.HEAD.equals(method) || HTTPRequest.DELETE.equals(method) || HTTPRequest.PUT.equals(method)
				|| HTTPRequest.TRACE.equals(method) || HTTPRequest.OPTIONS.equals(method) || HTTPRequest.PATCH.equals(method) ? method : HTTPRequest.POST;
		HttpUriRequestBase req = new HttpUriRequestBase(m, URI.create(r.getURL().toExternalForm()));

		for (Header h: r.getHeaders()) {
			req.addHeader(h.getName(), h.getValue());
		}

		boolean hasBody = r.getBody() != null || r.getFormFields() != null || r.getParts() != null;
		if (hasBody) {
			if (HTTPRequest.HEAD.equals(m) || HTTPRequest.TRACE.equals(m) || HTTPRequest.OPTIONS.equals(m)) {
				throw new IOException("the method [" + m.toLowerCase() + "] does not support a body");
			}
			req.setEntity(createEntity(r));
		}
		return req;
	}

	private static HttpEntity createEntity(HTTPRequest r) throws IOException {
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
			if (value instanceof InputStream) return new ByteArrayEntity(((InputStream) value).readAllBytes(), ct);
			if (value instanceof Resource) {
				Resource res = (Resource) value;
				try (InputStream is = res.getInputStream()) {
					return new ByteArrayEntity(is.readAllBytes(), ct);
				}
			}
			// a stream that was filled by the caller (TemporaryStream of the core)
			try {
				java.lang.reflect.Method m = value.getClass().getMethod("getInputStream");
				if (InputStream.class.isAssignableFrom(m.getReturnType())) {
					try (InputStream is = (InputStream) m.invoke(value)) {
						return new ByteArrayEntity(is.readAllBytes(), ct);
					}
				}
			}
			catch (NoSuchMethodException e) {
			}
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
	 * redirects: GET and HEAD follow redirects, other methods only follow a 303 (See Other), "lax" follows
	 * the redirects of every method
	 */
	private static final class RedirectStrategy extends org.apache.hc.client5.http.impl.DefaultRedirectStrategy {
		private final boolean lax;

		RedirectStrategy(boolean lax) {
			this.lax = lax;
		}

		@Override
		public boolean isRedirected(HttpRequest request, HttpResponse response, HttpContext context) throws org.apache.hc.core5.http.ProtocolException {
			if (!super.isRedirected(request, response, context)) return false;
			if (lax) return true;
			if (response.getCode() == 303) return true;
			String m = request.getMethod();
			return "GET".equalsIgnoreCase(m) || "HEAD".equalsIgnoreCase(m);
		}
	}

	/**
	 * a pooled connection that the server closed in the meantime is a transient condition, the request is
	 * sent again, a status code is never a reason to send the request again
	 */
	private static final class RetryStrategy implements org.apache.hc.client5.http.HttpRequestRetryStrategy {
		@Override
		public boolean retryRequest(HttpRequest request, IOException exception, int execCount, HttpContext context) {
			return execCount <= 2 && exception instanceof NoHttpResponseException;
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

	@Override
	public void releaseConnections() {
		List<PoolingHttpClientConnectionManager> old = new ArrayList<>(managers.values());
		managers.clear();
		CloseableHttpClient c = sharedClient;
		sharedClient = null;
		sharedManager = null;
		for (PoolingHttpClientConnectionManager cm: old) {
			cm.close();
		}
		if (c != null) {
			try {
				c.close();
			}
			catch (IOException e) {
			}
		}
	}

	@Override
	public void closeIdleConnections() {
		for (PoolingHttpClientConnectionManager cm: managers.values()) {
			cm.closeIdle(TimeValue.ofMilliseconds(POOL_CONN_TTL_MS));
			cm.closeExpired();
		}
	}

	@Override
	public void close() {
		releaseConnections();
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
		sct.setEL("config", config);
		return sct;
	}

	@Override
	public Struct getPoolStats() {
		Struct sct = Util.engine().getCreationUtil().createStruct();
		Struct routes = Util.engine().getCreationUtil().createStruct();
		int leased = 0, available = 0, pending = 0, max = 0;
		for (PoolingHttpClientConnectionManager cm: managers.values()) {
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
