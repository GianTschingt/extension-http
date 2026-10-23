package org.lucee.extension.http;

import java.nio.charset.Charset;

import lucee.loader.engine.CFMLEngine;
import lucee.loader.engine.CFMLEngineFactory;
import lucee.runtime.PageContext;
import lucee.runtime.util.Cast;

/**
 * Access to the functionality of the Lucee core, everything goes through the interfaces of the loader.
 */
final class Util {

	private Util() {
	}

	static CFMLEngine engine() {
		return CFMLEngineFactory.getInstance();
	}

	static Cast cast() {
		return engine().getCastUtil();
	}

	static boolean isEmpty(String str) {
		return str == null || str.length() == 0;
	}

	static boolean isEmpty(String str, boolean trim) {
		return str == null || (trim ? str.trim().length() == 0 : str.length() == 0);
	}

	static boolean toBooleanValue(Object obj, boolean defaultValue) {
		return cast().toBooleanValue(obj, defaultValue);
	}

	/**
	 * @return the charset of the current request, UTF-8 when there is none
	 */
	static Charset webCharset() {
		PageContext pc = engine().getThreadPageContext();
		if (pc != null) return pc.getWebCharset();
		return java.nio.charset.StandardCharsets.UTF_8;
	}

	static Charset toCharset(String charset, Charset defaultValue) {
		if (isEmpty(charset, true)) return defaultValue;
		try {
			return Charset.forName(charset.trim());
		}
		catch (Exception e) {
			return defaultValue;
		}
	}
}
