(ns io.schemamap.core
  (:gen-class)
  (:require [clojure.tools.logging :as log]
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

(defn determine-port-from-datasource [datasource]
  (throw (ex-info "TODO" {})))

(defn init!
  [{:keys [^DataSource datasource
           port-forward-host
           port-forward-remote-port
           port-forward-port
           port-forward-user
           port-forward-postgres?]
    :or   {port-forward-postgres? false
           port-forward-host      "pgtunnel.eu.schemamap.io"}}]
  (log/info "Migrating schemamap schema")
  (run-migrations! datasource)
  (log/info "Migrated schemamap schema")
  (let [session (if (and port-forward-remote-port port-forward-postgres?)
                  (do
                    (log/info "Starting Postgres SSH port forwarding to" port-forward-host)
                    (let [ssh-agent  (ssh/ssh-agent {:use-system-ssh-agent true})
                          local-port (or port-forward-port
                                         (determine-port-from-datasource datasource))]
                      (start-ssh-forwarding!
                       ssh-agent
                       {:host        port-forward-host
                        :username    port-forward-user
                        :local-port  local-port
                        :remote-port port-forward-remote-port})))
                  (log/debug "Skipping Postgres SSH port forwarding"))]
    {:session session}))

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

  (.disconnect session)
  )
