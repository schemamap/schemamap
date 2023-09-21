(ns io.schemamap.core-test
  (:require [io.schemamap.core :as sut]
            [hikari-cp.core :as hikari]
            [next.jdbc :as jdbc]
            [clojure.test :refer :all]))

(deftest integration
  (let [app-db-role "schemamap_test"
        sql-port    5432
        db-opts     {:adapter       "postgresql"
                     :database-name "schemamap_test"
                     :server-name   "127.0.0.1"
                     :port-number   sql-port}]
    (with-open [sm-datasource  (-> db-opts
                                   (assoc
                                    :username     "schemamap"
                                    :password     "schemamap")
                                   (hikari/make-datasource))
                app-datasource (-> db-opts
                                   (assoc
                                    :username     "schemamap_test"
                                    :password     "schemamap_test")
                                   (hikari/make-datasource))]
      (testing "SDK can be initialized, repeatedly"
        (dotimes [_ 2]
          (let [client
                (sut/init!
                 {:datasource               sm-datasource
                  :application-db-roles     #{app-db-role}
                  :port-forward-port        sql-port
                  :port-forward-remote-port 11111
                  :port-forward-user        (System/getenv "SCHEMAMAP_PORT_FWD_SSH_USERNAME")
                  ;; TODO: add test for this, set up special testing user
                  :port-forward-postgres?   false})]
            (try
              (is (= {:session nil} client))
              (finally (sut/close! client))))))
      (testing "after SDK initialization the app-db-role can use the DB interface via functions"
        (with-open [conn (jdbc/get-connection app-datasource)]
          (jdbc/execute-one! conn ["grant usage on schema public to schemamap"])
          (is (some?
               (jdbc/execute-one!
                conn
                ["select schemamap.update_function_definition('list_tenants', $$
                    select
                      1 as tenant_id,
                      'test_tenant' as tenant_short_name,
                      'Test Tenant' as tenant_display_name
                  $$)"])))
          (is (= [{:tenant_id "1",
                   :tenant_short_name "test_tenant",
                   :tenant_display_name "Test Tenant"}]
                 (jdbc/execute! conn ["select * from schemamap.list_tenants()"]))))))))
