(ns io.schemamap.core
  (:gen-class)
  (:require [next.jdbc :as jdbc]
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

(defn start-ssh-forwarding [agent host local-port remote-port]
  (let [session (ssh/session agent host {:port 2222
                                         :strict-host-key-checking :no})]
    (ssh/connect session)
    (ssh/forward-local-port [session local-port remote-port])
    session))

(defn determine-port-from-datasource [datasource]
  (throw (ex-info "TODO" {})))

(defn init!
  [{:keys [^DataSource datasource
           port-forward-host
           port-forward-remote-port
           port-forward-port
           port-forward-postgres?]
    :or   {port-forward-postgres? false
           port-forward-host      "pgtunnel.eu.schemamap.io"}}]
  (run-migrations! datasource)
  (let [session (when (and port-forward-remote-port port-forward-postgres?)
                  (let [ssh-agent  (ssh/ssh-agent {:use-system-ssh-agent true})
                        local-port (or port-forward-port
                                       (determine-port-from-datasource datasource))]
                    (start-ssh-forwarding
                     ssh-agent
                     port-forward-host
                     local-port
                     port-forward-remote-port)))]
    {:session session}))

(defn close! [{:keys [session]}]
  (when session
    (.disconnect session)))
