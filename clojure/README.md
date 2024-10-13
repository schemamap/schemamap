# Schemamap.io Clojure SDK

## Installation

Add to your deps.edn file as a:

Maven-dependency, via Clojars.org: 

``` clojure
io.schemamap/schemamap-clj {:mvn/version "0.4.1"}
```

Git-dependency:
``` clojure
io.github.schemamap/schemamap {:git/sha "$LATEST_COMMIT" :deps/root "clojure"}
```

## Usage

Integrate the `io.schemamap.core` namespace in your preferred dependency injection framework.

See tests for examples.

## Developing

For common operations, invoke `just`.

## Releasing

TLDR: `just release`

Run tests (assuming `devenv up` is running):

$ just test

Run the project's CI pipeline and build a JAR:

$ just ci

This will produce an updated pom.xml file with synchronized dependencies inside the META-INF directory inside target/classes and the JAR in target. 
You can update the version (and SCM tag) information in generated pom.xml by updating build.clj.

Deploy it to Clojars -- needs CLOJARS_USERNAME and CLOJARS_PASSWORD environment variables (requires the ci task be run first):

$ just release
