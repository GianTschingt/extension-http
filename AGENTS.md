# HTTP Extension — Agent Guide

Maven-based Lucee extension with the HTTP engine based on Apache HttpClient 5. It implements the `lucee.commons.net.http.HTTPClientEngine` interface of the Lucee loader and registers it with the manifest attribute `http-engine`.

## Folder Structure

- `source/java/src/` — Java source (`org.lucee.extension.http.HC5Engine` the engine, `HC5Response` the response, `Util` the access to the loader API)
- `source/java/pom.xml` — module POM (dependencies httpclient5, httpcore5, httpcore5-h2 and slf4j-api, bundled into the extension)
- `pom.xml` — root Maven build, extension manifest values, `.lex` packaging
- `build.xml` — Ant part of the build, writes the extension `MANIFEST.MF` (called from Maven)
- `tests/` — CFML integration tests (label: `http`), `_RecordingServer.cfc` is a helper (files starting with `_` are not run as tests)
- `CHANGELOG.md` — release notes, update for user-visible changes

## Build

Requires JDK 21 (the Lucee 9 jar has Java 21 class files, javac cannot read them with an older JDK) and Maven. The Lucee dependency (`org.lucee:lucee`, scope provided) must be available for the version in `pom.xml` (`luceeCoreVersion`).

```bash
mvn clean install -Dgoal=install
```

Output: `target/*.lex`

Versions and releases are handled by the GitHub workflow, which passes `-Drevision` (see "Versioning and releases" in `README.md`). A manual deploy by maintainers uses a local `maven-deploy.sh` (not committed), which needs `MAVEN_USERNAME`, `MAVEN_PASSWORD` and `GPG_PASSPHRASE` in the environment. Never commit credentials.

## Test

CI (`.github/workflows/main.yml`) builds and runs, with the extension installed, the Lucee tests labelled `http` and `cfhttp,ssl` plus the tests in `tests/` with [script-runner](https://github.com/lucee/script-runner) and an httpbin service, against the Lucee versions in the variable `LUCEE_TEST_VERSIONS_9` (organization or repository). There is no fallback version, without the variable the build fails.

## Notes

- The extension only uses the loader API (through `org.lucee.extension.http.Util`), never core classes.
- Minimum Lucee version is in `luceeCoreVersion` in `pom.xml`, it must be a Lucee version that knows the `http-engine` manifest attribute.
- Behaviour must stay identical to the HttpClient 4 based engine that was in the Lucee core until Lucee 8.
- The lite `.lex` excludes `maven/` on purpose (the same convention as the other extensions), Lucee resolves the libraries from Maven.
