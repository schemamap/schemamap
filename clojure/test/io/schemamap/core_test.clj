(ns io.schemamap.core-test
  (:require [io.schemamap.core :as sut]
            [hikari-cp.core :as hikari]
            [next.jdbc :as jdbc]
            io.schemamap.test-util ;; loading for side-effects
            [clojure.test :refer :all]
            [clojure.java.io :as io]
            [next.jdbc.result-set :as jdbc.rs]))

(deftest valid-pg-role-name?
  (are [input expected] (= expected (sut/valid-pg-role-name? input))
    "postgres"                       true
    "schemamap_test"                 true
    "somerole42"                     true
    "Robert; DROP TABLE Students;--" false
    ""                               false
    nil                              false))

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
                                    :password     "schemamap_test"
                                    :maximum-pool-size 5)
                                   (hikari/make-datasource))]
      (testing "SDK can be initialized, repeatedly"
        (dotimes [nth-init 2]
          (let [client
                (sut/init!
                 {:datasource               sm-datasource
                  :application-db-roles     #{app-db-role}
                  :i18n (nth [(io/file "../fixtures/adventureworks_i18n.json")
                              "{\"test\": 42}"]
                             nth-init)})]
            (try
              (is (= {} client))
              (finally (sut/close! client))))))
      (testing "after SDK initialization the app-db-role can use the DB interface via functions"
        (with-open [conn (jdbc/get-connection app-datasource)]
          (testing "i18n value can be fetched"
            (is (= {:test 42}
                   (-> conn
                       (jdbc/execute-one!
                        ["select schemamap.i18n() as i18n"])
                       :i18n))))
          (testing "updating function definitions"
            (is (some?
                 (jdbc/execute-one!
                  conn
                  ["select schemamap.update_function_definition('list_tenants', $$
                    select
                      1 as tenant_id,
                      'test_tenant' as tenant_short_name,
                      'Test Tenant' as tenant_display_name,
                      'en_US' as tenant_locale,
                      null::jsonb as tenant_data
                  $$)"])))
            (is (= [{:tenant_id           "1",
                     :tenant_short_name   "test_tenant",
                     :tenant_display_name "Test Tenant"
                     :tenant_locale       "en_US"
                     :tenant_data         nil}]
                   (jdbc/execute! conn ["select * from schemamap.list_tenants()"]))))
          (testing "asking for master data entity candidates"
            ;; run a full vaccum so row count estimates are closer to reality
            (jdbc/execute! conn ["vacuum full analyze"])
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
                      from schemamap.master_data_entity_candidates() limit 10;"]))))
          (testing "querying schema metadata overview"
            (is (=
                 {:constraints
                  [{:definition "UNIQUE (rowguid)",
                    :name       "document_rowguid_key",
                    :type       "u"}],
                  :schema_name       "production",
                  :column_description
                  "ROWGUIDCOL number uniquely identifying the record. Required for FileStream.",
                  :object_type       "r",
                  :not_null          true,
                  :table_description "Product maintenance documents.",
                  :data_type         "uuid",
                  :indexes           [{:name "document_rowguid_key", :is_unique true}],
                  :column_name       "rowguid",
                  :table_name        "document",
                  :default_value     "uuid_generate_v1()"}
                 (jdbc/execute-one!
                  conn
                  ["select *
                      from schemamap.schema_metadata_overview
                      where indexes is not null and constraints is not null
                      order by jsonb_array_length(constraints) desc nulls last
                      limit 1"]
                  {:builder-fn jdbc.rs/as-unqualified-maps}))))
          (testing "asking what-if questions by updating schema in transactions"
              ;; baseline: how many columns do we know about per schema?
            (let [verify-baseline! (fn [connectable]
                                     (is (= [{:schema_name "sales", :count 233}
                                             {:schema_name "production", :count 208}
                                             {:schema_name "pr", :count 188}
                                             {:schema_name "sa", :count 150}
                                             {:schema_name "humanresources", :count 118}
                                             {:schema_name "person", :count 94}
                                             {:schema_name "pe", :count 82}
                                             {:schema_name "purchasing", :count 67}
                                             {:schema_name "pu", :count 51}
                                             {:schema_name "hr", :count 45}]
                                            (jdbc/execute!
                                             connectable
                                             ["select schema_name, count(*) from schemamap.schema_metadata_overview group by 1 order by 2 desc"]
                                             {:builder-fn jdbc.rs/as-unqualified-maps}))))]
              (jdbc/with-transaction [tx conn {:rollback-only true}]
                (verify-baseline! tx)

                  ;; mutate the schema
                (jdbc/execute-one! tx ["drop table production.document cascade"])

                  ;; refresh the materialized view
                (jdbc/execute-one! tx ["select * from schemamap.update_schema_metadata_overview(concurrently := false)"])

                (is (= [{:schema_name "sales", :count 233}

                          ;; reduced column counts caused by the cascading table drop
                        {:schema_name "production", :count 195}
                        {:schema_name "pr", :count 175}

                        {:schema_name "sa", :count 150}
                        {:schema_name "humanresources", :count 118}
                        {:schema_name "person", :count 94}
                        {:schema_name "pe", :count 82}
                        {:schema_name "purchasing", :count 67}
                        {:schema_name "pu", :count 51}
                        {:schema_name "hr", :count 45}]
                       (jdbc/execute!
                        tx
                        ["select schema_name, count(*) from schemamap.schema_metadata_overview group by 1 order by 2 desc"]
                        {:builder-fn jdbc.rs/as-unqualified-maps}))))
                ;; after the transaction rolls back, we get the original baseline
              (verify-baseline! conn))))))))
