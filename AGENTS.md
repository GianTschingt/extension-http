# HTTP Extension — Agent Guide

Maven-based Lucee extension with the HTTP engine based on Apache HttpClient 5. It implements the `lucee.commons.net.http.HTTPClientEngine` interface of the Lucee loader and registers it with the manifest attribute `http-engine`.

## Folder Structure

- `source/java/src/` — Java source (`org.lucee.extension.http.HC5Engine` and the appenders and layouts below it)
- `source/java/pom.xml` — module POM (dependencies httpclient5, httpcore5, httpcore5-h2 and slf4j-api, bundled into the extension)
- `pom.xml` — root Maven build, extension manifest values, `.lex` packaging
- `build.xml` — Ant part of the build, writes the extension `MANIFEST.MF` (called from Maven)
- `tests/` — CFML integration tests (label: `http`)
- `CHANGELOG.md` — release notes, update for user-visible changes

## Build

Requires JDK 21 (the Lucee 9 jar has Java 21 class files, javac cannot read them with an older JDK) and Maven. The Lucee dependency (`org.lucee:lucee`, scope provided) must be available for the version in `pom.xml` (`luceeCoreVersion`).

```bash
mvn clean install -Dgoal=install
```

Output: `target/*.lex`

Maintainers deploy with a local `maven-deploy.sh` (not committed), which needs `MAVEN_USERNAME`, `MAVEN_PASSWORD` and `GPG_PASSPHRASE` in the environment. Never commit credentials.

## Test

CI (`.github/workflows/main.yml`) builds once and runs the tests with [script-runner](https://github.com/lucee/script-runner) against the Lucee versions defined in the repository variable `LUCEE_TEST_VERSIONS_9`.

## Notes

- The extension only uses the loader API (through `org.lucee.extension.http.Util`), never core classes.
- Minimum Lucee version is in `luceeCoreVersion` in `pom.xml`, it must be a Lucee version that knows the `http-engine` manifest attribute.
- Behaviour must stay identical to the HttpClient 4 based engine that was in the Lucee core until Lucee 8.
