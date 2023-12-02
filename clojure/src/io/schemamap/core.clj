(ns io.schemamap.core
  (:gen-class)
  (:require [clojure.tools.logging :as log]
            [next.jdbc :as jdbc]
            [clj-ssh.ssh :as ssh])
  (:import
   (org.flywaydb.core Flyway)
   (javax.sql DataSource)))

(defn run-migrations! [datasource]
  (.. (Flyway/configure)
      (defaultSchema "schemamap")
      (locations (into-array String ["classpath:io/schemamap/db/migrations"]))
      (createSchemas true)
      (dataSource datasource)
      (load)
      (migrate)))

(defn start-ssh-forwarding!
  [agent {:keys [host username local-port remote-port
                 connect-timeout]
          :or   {connect-timeout 5000}}]
  (let [ssh-service-port 22 #_2222
        session          (ssh/session agent host {:port                     ssh-service-port
                                                  :username                 username
                                                  :strict-host-key-checking :no})]
    (log/infof "Trying connecting to %s@%s:%s" username host ssh-service-port)
    (ssh/connect session connect-timeout)
    (log/infof "Connected to %s@%s:%s" username host ssh-service-port)

    (log/infof "Forwarding local port %s to remote port %s" local-port remote-port)
    (ssh/forward-remote-port session remote-port local-port)
    session))

(defn read-i18n-string!
  ^String [input]
  (cond
    (string? input)
    input

    (instance? java.io.File input)
    (slurp input)

    ;; explicitly not implementing Clojure map -> JSON string
    ;; as that would require a runtime dependency on a particular JSON library

    :else
    (throw (ex-info "Unsupported i18n input provided, please provide a java.io.File or a JSON string"
                    {:input input
                     :class (class input)}))))

(defn valid-pg-role-name? [role-name]
  (boolean
   (some->> role-name
            (re-matches #"^[a-zA-Z_][a-zA-Z0-9_]*$"))))

(defn alter-schemamap-schema!
  [{:keys [^DataSource datasource application-db-roles i18n]}]
  (with-open [conn (jdbc/get-connection datasource)]
    (doseq [role application-db-roles]
      (when-not (valid-pg-role-name? role)
        (throw (ex-info "Invalid role name provided" {:role-name role})))

      (log/info "Granting schemamap schema usage permissions to role:" application-db-roles)
      (jdbc/execute! conn [(format "grant usage on schema schemamap to %s" role)])
      (jdbc/execute! conn [(format "grant execute on all functions in schema schemamap to %s" role)])
      (jdbc/execute! conn [(format "grant select on schemamap.i18n_stored, schemamap.schema_metadata_overview to %s" role)]))

    (when i18n
      (log/info "Overriding schemamap.i18n() value")
      (jdbc/execute! conn ["select schemamap.update_i18n(?::jsonb)" (read-i18n-string! i18n)]))))

(defn maybe-ssh-port-forward-postgres!
  [{:keys [port-forward-host
           port-forward-remote-port
           port-forward-port
           port-forward-user
           port-forward-postgres?]
    :or   {port-forward-postgres? false
           port-forward-host      "pgtunnel.eu.schemamap.io"}}]
  (if (and port-forward-remote-port port-forward-postgres?)
    (do
      (log/info "Starting Postgres SSH port forwarding to" port-forward-host)
      (let [ssh-agent  (ssh/ssh-agent {:use-system-ssh-agent true})
            local-port port-forward-port]
        (start-ssh-forwarding!
         ssh-agent
         {:host        port-forward-host
          :username    port-forward-user
          :local-port  local-port
          :remote-port port-forward-remote-port})))
    (log/debug "Skipping Postgres SSH port forwarding")))

(defn init!
  [{:keys [^DataSource datasource
           i18n
           port-forward-host
           port-forward-remote-port
           port-forward-port
           port-forward-user
           port-forward-postgres?
           application-db-roles]
    :as   params}]
  (log/info "Migrating schemamap schema")
  (run-migrations! datasource)
  (log/info "Migrated schemamap schema")

  (alter-schemamap-schema! params)

  {:session (maybe-ssh-port-forward-postgres! params)})

;; TODO: implement java.io.Closeable to allow `with-open` macro usage
(defn close! [{:keys [session]}]
  (when session
    (.disconnect session)))

(comment
  (def ssh-agent (ssh/ssh-agent {:use-system-ssh-agent true}))
  (.getIdentityNames ssh-agent)

  (def session
    (start-ssh-forwarding!
     ssh-agent
     {:host            "pgtunnel.eu.schemamap.io"
      :username        "pgtunnel_frutico_krisz"
      :local-port      5437
      :remote-port     11111
      :connect-timeout 2000}))

  (.disconnect session))
