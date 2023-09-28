(ns io.schemamap.test-util
  (:require [io.schemamap.core :as sut]
            [hikari-cp.core :as hikari]
            [next.jdbc :as jdbc]
            [jsonista.core :as json]
            [next.jdbc.result-set :as rs]
            [clojure.test :refer :all]
            [clojure.java.io :as io]))

(def json-object-mapper (json/object-mapper {:decode-key-fn true}))
(defn json-read! [object] (json/read-value object json-object-mapper))

(defn <-pgobject
  "Transform PGobject containing `json` or `jsonb` value to Clojure
  data."
  [^org.postgresql.util.PGobject v]
  (let [type  (.getType v)
        value (.getValue v)]
    (if (#{"jsonb" "json"} type)
      (when value
        (with-meta (json/read-value value json-object-mapper) {:pgtype type}))
      value)))

(extend-protocol rs/ReadableColumn
  org.postgresql.util.PGobject
  (read-column-by-label [^org.postgresql.util.PGobject v _]
    (<-pgobject v))
  (read-column-by-index [^org.postgresql.util.PGobject v _2 _3]
    (<-pgobject v)))
