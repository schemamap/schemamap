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
                                    :password     "schemamap"
                                    :minimum-idle 1
                                    :maximum-pool-size 2)
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
          (testing "updating function definitions"
            (is (some?
                 (jdbc/execute-one!
                  conn
                  ["select schemamap.update_function_definition('list_tenants', $$
                    select
                      1 as tenant_id,
                      'test_tenant' as tenant_short_name,
                      'Test Tenant' as tenant_display_name
                  $$)"])))
            (is (= [{:tenant_id           "1",
                     :tenant_short_name   "test_tenant",
                     :tenant_display_name "Test Tenant"}]
                   (jdbc/execute! conn ["select * from schemamap.list_tenants()"]))))
          (testing "asking for master data entity candidates"
            ;; run a full vaccum so row count estimates are closer to reality
            (jdbc/execute! conn ["VACUUM(FULL, ANALYZE, VERBOSE)"])
            (is (= [{:schema_name         "production",
                     :table_name          "product",
                     :approx_rows         504,
                     :foreign_key_count   14,
                     :rounded_probability 1.00M}
                    {:schema_name         "humanresources",
                     :table_name          "employee",
                     :approx_rows         290,
                     :foreign_key_count   6,
                     :rounded_probability 0.71M}
                    {:schema_name         "sales",
                     :table_name          "salesterritory",
                     :approx_rows         10,
                     :foreign_key_count   5,
                     :rounded_probability 0.68M}
                    {:schema_name         "person",
                     :table_name          "person",
                     :approx_rows         19972,
                     :foreign_key_count   7,
                     :rounded_probability 0.67M}
                    {:schema_name         "sales",
                     :table_name          "salesperson",
                     :approx_rows         17,
                     :foreign_key_count   4,
                     :rounded_probability 0.64M}
                    {:schema_name         "production",
                     :table_name          "unitmeasure",
                     :approx_rows         38,
                     :foreign_key_count   4,
                     :rounded_probability 0.64M}
                    {:schema_name         "sales",
                     :table_name          "currency",
                     :approx_rows         105,
                     :foreign_key_count   3,
                     :rounded_probability 0.61M}
                    {:schema_name         "production",
                     :table_name          "productmodel",
                     :approx_rows         128,
                     :foreign_key_count   3,
                     :rounded_probability 0.61M}
                    {:schema_name         "person",
                     :table_name          "countryregion",
                     :approx_rows         238,
                     :foreign_key_count   3,
                     :rounded_probability 0.61M}
                    {:schema_name         "person",
                     :table_name          "businessentity",
                     :approx_rows         20777,
                     :foreign_key_count   5,
                     :rounded_probability 0.59M}]
                   ;; NOTE: rounding probability so test suite is more stable across envs/architectures
                   (jdbc/execute!
                    conn
                    ["select schema_name, table_name, approx_rows, foreign_key_count,
                             round(probability_master_data::numeric, 2) as rounded_probability
                      from schemamap.master_date_entity_candidates() limit 10;"])))))))))
