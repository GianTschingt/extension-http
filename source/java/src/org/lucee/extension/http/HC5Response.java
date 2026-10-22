package org.lucee.extension.http;

import java.io.ByteArrayInputStream;
import java.io.FilterInputStream;
import java.io.IOException;
import java.io.InputStream;
import java.net.MalformedURLException;
import java.net.URI;
import java.net.URL;
import java.nio.charset.Charset;
import java.util.List;

import org.apache.hc.client5.http.impl.classic.CloseableHttpClient;
import org.apache.hc.core5.http.ClassicHttpResponse;
import org.apache.hc.core5.http.HttpEntity;

import lucee.commons.io.res.ContentType;
import lucee.commons.net.http.HTTPResponse;
import lucee.commons.net.http.Header;
import lucee.runtime.type.Array;

/**
 * response of the HTTP engine based on Apache HttpClient 5
 */
final class HC5Response implements HTTPResponse {

	private static final class HeaderImpl implements Header {
		private final String name;
		private final String value;

		HeaderImpl(String name, String value) {
			this.name = name;
			this.value = value;
		}

		@Override
		public String getName() {
			return name;
		}

		@Override
		public String getValue() {
			return value;
		}

		@Override
		public String toString() {
			return name + ": " + value;
		}
	}

	private static final class ContentTypeImpl implements ContentType {
		private final String mimeType;
		private final String charset;

		ContentTypeImpl(String mimeType, String charset) {
			this.mimeType = mimeType;
			this.charset = charset;
		}

		@Override
		public String getMimeType() {
			return mimeType;
		}

		@Override
		public String getCharset() {
			return charset;
		}
	}

	private final ClassicHttpResponse rsp;
	private final CloseableHttpClient client;
	private final URL url;
	private final URL target;
	private final List<URI> locations;
	private final Header[] headers;
	// the content, when it had to be read to get its length
	private byte[] buffered;
	private boolean closed;

	/**
	 * @param client the client to close when the response is closed, null when the client is shared
	 * @param url the URL of the request
	 * @param target the URL of the response, after the redirects
	 * @param locations the URLs of the redirects that were followed
	 */
	HC5Response(ClassicHttpResponse rsp, CloseableHttpClient client, URL url, URI target, List<URI> locations) throws MalformedURLException {
		this.rsp = rsp;
		this.client = client;
		this.url = url;
		this.target = target.toURL();
		this.locations = locations;

		// HttpClient decompresses the content (gzip, deflate, ...) and replaces the entity with one that has no
		// content encoding anymore, only then the headers that describe the compressed content are removed (like
		// HttpClient 4 did). A response without content (HEAD, 204, 304) is not decompressed, its headers stay.
		HttpEntity entity = rsp.getEntity();
		boolean decoded = rsp.containsHeader("Content-Encoding") && entity != null && entity.getContentEncoding() == null;

		org.apache.hc.core5.http.Header[] src = rsp.getHeaders();
		List<Header> list = new java.util.ArrayList<>();
		for (int i = 0; src != null && i < src.length; i++) {
			String name = src[i].getName();
			if (decoded && (name.equalsIgnoreCase("Content-Encoding") || name.equalsIgnoreCase("Content-Length") || name.equalsIgnoreCase("Content-MD5"))) continue;
			list.add(new HeaderImpl(name, src[i].getValue()));
		}
		headers = list.toArray(new Header[list.size()]);
	}

	@Override
	public String getContentAsString() throws IOException {
		return getContentAsString(null);
	}

	@Override
	public String getContentAsString(String charset) throws IOException {
		byte[] data = getContentAsByteArray();
		Charset cs = Util.toCharset(charset, null);
		if (cs == null) cs = Util.toCharset(getCharset(), Util.webCharset());
		return new String(data, cs);
	}

	@Override
	public InputStream getContentAsStream() throws IOException {
		if (buffered != null) return new ByteArrayInputStream(buffered);
		HttpEntity e = rsp.getEntity();
		if (e == null) return null;
		// closing the stream releases the connection and closes a client of its own
		return new FilterInputStream(e.getContent()) {
			@Override
			public void close() throws IOException {
				try {
					super.close();
				}
				finally {
					HC5Response.this.close();
				}
			}
		};
	}

	@Override
	public byte[] getContentAsByteArray() throws IOException {
		if (buffered != null) return buffered;
		HttpEntity e = rsp.getEntity();
		if (e == null) return new byte[0];
		try (InputStream is = e.getContent()) {
			buffered = is.readAllBytes();
		}
		return buffered;
	}

	@Override
	public Array getLocations() {
		if (locations == null || locations.isEmpty()) return null;
		Array arr = Util.engine().getCreationUtil().createArray();
		for (URI l: locations) {
			arr.appendEL(l.toString());
		}
		return arr;
	}

	@Override
	public ContentType getContentType() {
		Header h = getLastHeaderIgnoreCase("Content-Type");
		if (h == null || Util.isEmpty(h.getValue(), true)) return null;
		String[] parts = h.getValue().split(";");
		String mime = parts[0].trim();
		String charset = null;
		for (int i = 1; i < parts.length; i++) {
			String p = parts[i].trim();
			if (p.toLowerCase().startsWith("charset=")) {
				charset = p.substring(8).trim();
				if (charset.length() > 1 && charset.startsWith("\"") && charset.endsWith("\"")) charset = charset.substring(1, charset.length() - 1);
			}
		}
		return new ContentTypeImpl(mime, charset);
	}

	@Override
	public Header getLastHeader(String name) {
		for (int i = headers.length - 1; i >= 0; i--) {
			if (name.equals(headers[i].getName())) return headers[i];
		}
		return null;
	}

	@Override
	public Header getLastHeaderIgnoreCase(String name) {
		for (int i = headers.length - 1; i >= 0; i--) {
			if (name.equalsIgnoreCase(headers[i].getName())) return headers[i];
		}
		return null;
	}

	@Override
	public String getCharset() {
		ContentType ct = getContentType();
		if (ct != null && !Util.isEmpty(ct.getCharset(), true)) return ct.getCharset();
		return Util.webCharset().name();
	}

	@Override
	public long getContentLength() throws IOException {
		Header h = getLastHeaderIgnoreCase("Content-Length");
		// an invalid header is an unknown length, like the built-in engine
		if (h != null) return toLong(h.getValue(), -1);
		if (buffered != null) return buffered.length;
		HttpEntity e = rsp.getEntity();
		if (e == null) return 0;
		long length = e.getContentLength();
		if (length >= 0) return length;
		// the length is only known after reading the content, it is kept, so it can still be read afterwards
		try (InputStream is = e.getContent()) {
			buffered = is.readAllBytes();
		}
		return buffered.length;
	}

	private static long toLong(String value, long defaultValue) {
		if (value == null) return defaultValue;
		String str = value.trim();
		if (str.isEmpty()) return defaultValue;
		for (int i = 0; i < str.length(); i++) {
			if (!Character.isDigit(str.charAt(i))) return defaultValue;
		}
		if (str.length() > 18) return defaultValue;
		return Long.parseLong(str);
	}

	@Override
	public URL getURL() {
		return url;
	}

	@Override
	public URL getTargetURL() {
		return target;
	}

	@Override
	public int getStatusCode() {
		return rsp.getCode();
	}

	@Override
	public String getStatusText() {
		String reason = rsp.getReasonPhrase();
		return reason == null ? "" : reason;
	}

	@Override
	public String getProtocolVersion() {
		return String.valueOf(rsp.getVersion());
	}

	@Override
	public String getStatusLine() {
		return (getProtocolVersion() + " " + rsp.getCode() + " " + getStatusText()).trim();
	}

	@Override
	public Header[] getAllHeaders() {
		return headers;
	}

	@Override
	public void close() throws IOException {
		if (closed) return;
		closed = true;
		try {
			rsp.close();
		}
		finally {
			if (client != null) client.close();
		}
	}
}
