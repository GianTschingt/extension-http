package org.lucee.extension.http;

import java.net.URL;
import java.util.Collections;
import java.util.List;
import java.util.Map;

import lucee.commons.net.http.HTTPResponse;
import lucee.runtime.PageContext;
import lucee.runtime.debug.Debugger;
import lucee.runtime.listener.ApplicationContext;

/**
 * The entry of one HTTP call in the debugging output (LDEV-2822), shown in the section "HTTP" next to
 * the other sections of the debugging template.
 * <p>
 * An entry has the method, the host and the path of the URL (never the query string, the user info or
 * the fragment, they can have tokens and passwords), the status code, the duration and whether the
 * connection of the pool was reused. It is only recorded when debugging is enabled for the current
 * request, a call without debugging does not do more than one check.
 * <p>
 * It goes through the generic data of the debugger of the Lucee loader API, the same as the function
 * <code>DebugAdd()</code>.
 */
final class HC5Debug {

	/** the name of the section in the debugging output */
	static final String CATEGORY = "HTTP";

	private final Debugger debugger;
	private final long start = System.nanoTime();
	private String method;
	private String target;
	// every exchange of the call (the redirects too) used a connection that was used before
	private boolean exchanged;
	private boolean reused = true;

	private HC5Debug(Debugger debugger) {
		this.debugger = debugger;
	}

	/**
	 * @return the entry for the current request, null when there is no request or debugging is not enabled
	 *         for it
	 */
	static HC5Debug begin() {
		PageContext pc = Util.engine().getThreadPageContext();
		if (pc == null) return null;
		ApplicationContext ac = pc.getApplicationContext();
		// the same check the core makes before it collects debugging data of a request, a debugging option
		// of the application (or the server) is set
		if (ac == null || ac.getDebugOptions() <= 0) return null;
		Debugger debugger = pc.getDebugger();
		return debugger == null ? null : new HC5Debug(debugger);
	}

	/**
	 * the request that is sent, the first one of the call
	 */
	void target(String method, URL url) {
		this.method = method;
		this.target = hostAndPath(url);
	}

	/**
	 * an exchange with the server is done (a response or an error of the server is there), the redirects
	 * of a call are more than one
	 * 
	 * @param reused if the connection of the exchange came from the pool, null when it is not known
	 */
	void exchange(Boolean reused) {
		if (reused == null) return;
		exchanged = true;
		if (!reused) this.reused = false;
	}

	/**
	 * adds the entry to the debugging data
	 * 
	 * @param response the response of the call, null when the call failed
	 * @param failure the error of the call, null when there is none
	 */
	void end(HTTPResponse response, Throwable failure) {
		// the request never went out, for example the request was not valid
		if (target == null) return;
		long ms = (System.nanoTime() - start) / 1_000_000L;

		StringBuilder value = new StringBuilder();
		if (response != null) value.append(response.getStatusCode());
		else value.append("failed (").append(failure == null ? "no response" : failure.getClass().getSimpleName()).append(')');
		value.append(", ").append(ms).append(" ms");
		if (exchanged) value.append(reused ? ", connection reused" : ", new connection");

		// the name has the position of the call in the request, so the entries of the same URL do not get
		// joined into one
		Map<String, Map<String, List<String>>> data = debugger.getGenericData();
		Map<String, List<String>> section = data == null ? null : data.get(CATEGORY);
		int position = (section == null ? 0 : section.size()) + 1;
		debugger.addGenericData(CATEGORY, Collections.singletonMap("#" + position + " " + method + " " + target, value.toString()));
	}

	/**
	 * host (with the port when the URL has one) and path, without the user info, the matrix parameters
	 * of the path, the query string and the fragment
	 */
	static String hostAndPath(URL url) {
		StringBuilder sb = new StringBuilder(url.getHost());
		if (url.getPort() != -1) sb.append(':').append(url.getPort());
		String path = url.getPath();
		if (Util.isEmpty(path)) path = "/";
		sb.append(path.replaceAll(";[^/]*", ""));
		return sb.toString();
	}
}
