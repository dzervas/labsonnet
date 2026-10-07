from support import JsonnetTestCase


class CNPGTests(JsonnetTestCase):
    def test_cluster_nested_merges_preserve_extensions(self):
        cluster = self.render_case("cnpg", "configured_cluster")["cluster"]
        spec = cluster["spec"]
        postgres = spec["postgresql"]

        self.assertEqual(spec["instances"], 4)
        self.assertEqual(
            postgres["parameters"],
            {"work_mem": "32MB", "max_connections": "200"},
        )
        self.assertEqual(
            postgres["shared_preload_libraries"],
            ["pg_stat_statements", "auto_explain", "pg_cron"],
        )
        self.assertEqual(
            [extension["name"] for extension in postgres["extensions"]],
            ["postgis", "pg_trgm", "plpgsql"],
        )
        self.assertEqual(
            postgres["extensions"][0]["image"],
            {
                "reference": "registry.example/postgis:18",
                "pullPolicy": "IfNotPresent",
            },
        )
        self.assertEqual(postgres["extensions"][0]["extension_control_path"], ["share"])
        self.assertEqual(postgres["extensions"][0]["dynamic_library_path"], ["lib"])
        self.assertEqual(spec["imageCatalogRef"]["major"], 18)
        self.assertNotIn("image", postgres["extensions"][2])

    def assert_tenant_relationships(
        self, tenant, database_name, app_namespace, resource_name, secret_name
    ):
        role = tenant["role"]
        database = tenant["database"]
        credentials = tenant["roleCredentials"]
        role_spec = role["spec"]
        database_spec = database["spec"]
        credential_spec = credentials["spec"]
        target = credential_spec["target"]
        role_data = target["template"]["data"]

        self.assertEqual(database["metadata"]["name"], resource_name)
        self.assertEqual(role["metadata"]["name"], resource_name)
        self.assertEqual(role_spec["cluster"], database_spec["cluster"])
        self.assertEqual(role_spec["name"], database_spec["owner"])
        self.assertEqual(database_spec["name"], database_name)
        self.assertEqual(role_spec["passwordSecret"]["name"], secret_name)
        self.assertEqual(target["name"], secret_name)
        self.assertEqual(role["metadata"]["namespace"], "postgres")
        self.assertEqual(database["metadata"]["namespace"], "postgres")
        self.assertEqual(credentials["metadata"]["namespace"], "postgres")
        self.assertEqual(role_spec["databaseRoleReclaimPolicy"], "retain")
        self.assertEqual(database_spec["databaseReclaimPolicy"], "retain")
        self.assertEqual(target["template"]["type"], "kubernetes.io/basic-auth")
        self.assertEqual(role_data["username"], role_spec["name"])
        self.assertEqual(role_data["password"], "{{ .password }}")

        if app_namespace == "postgres":
            self.assertEqual(tenant["applicationCredentials"], {})
            app_data = role_data
        else:
            application = tenant["applicationCredentials"]
            application_spec = application["spec"]
            self.assertEqual(application["metadata"]["namespace"], app_namespace)
            self.assertEqual(application_spec["target"]["name"], secret_name)
            app_data = application_spec["target"]["template"]["data"]

        host = "shared-rw.postgres.svc"
        self.assertEqual(app_data["username"], role_spec["name"])
        self.assertEqual(app_data["database"], database_spec["name"])
        self.assertEqual(app_data["host"], host)
        self.assertEqual(app_data["port"], "5432")
        self.assertEqual(app_data["password"], "{{ .password }}")
        uri_password = '{{ .password | urlquery | replace "+" "%20" }}'
        self.assertEqual(
            app_data["uri"],
            f"postgresql://{role_spec['name']}:{uri_password}@{host}:5432/{database_spec['name']}",
        )

    def test_tenant_credentials_match_role_database_and_application(self):
        cases = [
            {
                "name": "remote cross namespace",
                "fixture": "remote_cross_namespace",
                "database": "affine",
                "app_namespace": "apps",
                "resource": "affine-tenant",
                "secret": "affine-credentials",
                "mode": "remote",
            },
            {
                "name": "remote same namespace",
                "fixture": "remote_same_namespace",
                "database": "outline",
                "app_namespace": "postgres",
                "resource": "shared-outline",
                "secret": "outline-postgres",
                "mode": "remote",
            },
            {
                "name": "generated cross namespace",
                "fixture": "generated_cross_namespace",
                "database": "paperless",
                "app_namespace": "paperless",
                "resource": "shared-paperless",
                "secret": "paperless-postgres",
                "mode": "generated",
            },
            {
                "name": "generated same namespace",
                "fixture": "generated_same_namespace",
                "database": "grafana",
                "app_namespace": "postgres",
                "resource": "shared-grafana",
                "secret": "grafana-postgres",
                "mode": "generated",
            },
        ]

        for case in cases:
            with self.subTest(case=case["name"]):
                tenant = self.render_case("cnpg", case["fixture"])
                self.assert_tenant_relationships(
                    tenant,
                    case["database"],
                    case["app_namespace"],
                    case["resource"],
                    case["secret"],
                )

                credentials = tenant["roleCredentials"]["spec"]
                if case["mode"] == "generated":
                    self.assertNotIn("secretStoreRef", credentials)
                    self.assertEqual(credentials["refreshPolicy"], "OnChange")
                if case["mode"] == "remote":
                    self.assertEqual(
                        credentials["secretStoreRef"],
                        {"name": "app-secrets", "kind": "ClusterSecretStore"},
                    )
                    self.assertEqual(
                        credentials["data"],
                        [
                            {
                                "secretKey": "password",
                                "remoteRef": {"key": "app", "property": "password"},
                            }
                        ],
                    )
                    self.assertEqual(credentials["refreshPolicy"], "Periodic")
                    if case["app_namespace"] != "postgres":
                        app_spec = tenant["applicationCredentials"]["spec"]
                        self.assertEqual(
                            app_spec["secretStoreRef"], credentials["secretStoreRef"]
                        )
                        self.assertEqual(app_spec["data"], credentials["data"])
                elif case["app_namespace"] == "postgres":
                    generator = credentials["dataFrom"][0]["sourceRef"]["generatorRef"]
                    self.assertEqual(generator["kind"], "Password")
                    self.assertEqual(generator["name"], "postgres-password")
                else:
                    generator = credentials["dataFrom"][0]["sourceRef"]["generatorRef"]
                    self.assertEqual(generator["kind"], "ClusterGenerator")
                    self.assertEqual(generator["name"], "postgres-password")
                    app_spec = tenant["applicationCredentials"]["spec"]
                    self.assertEqual(
                        app_spec["secretStoreRef"],
                        {"name": "postgres-secrets", "kind": "ClusterSecretStore"},
                    )
                    self.assertEqual(
                        app_spec["data"][0]["remoteRef"],
                        {"key": case["secret"], "property": "password"},
                    )
                    self.assertEqual(app_spec["refreshInterval"], "1m")
                    self.assertNotIn("dataFrom", app_spec)

    def test_invalid_tenant_identity_and_replication_configuration_fail(self):
        cases = [
            ("invalid_database_identity", "tenant databaseSpec must not override"),
            ("invalid_role_identity", "tenant roleSpec must not override"),
            (
                "invalid_generated_replication",
                "generated credentials require generatorName and a replicationStore",
            ),
        ]
        for fixture, diagnostic in cases:
            with self.subTest(fixture=fixture):
                self.assert_render_failure("cnpg", fixture, diagnostic)
