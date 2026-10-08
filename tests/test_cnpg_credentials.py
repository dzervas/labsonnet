from support import JsonnetTestCase


class CNPGCredentialTests(JsonnetTestCase):
    def test_generated_password_flow_and_scoped_reader_grants(self):
        flows = self.render_case("cnpg", "generated_flows")
        for case, reader_name in (("defaultReader", "billing-export"), ("customReader", "billing-reader")):
            with self.subTest(case=case):
                setup = flows[case]["infrastructure"]
                tenant = flows[case]["tenant"]
                generator = setup["passwordGenerator"]
                reader = setup["credentialReader"]
                store = setup["credentialStore"]
                provider = store["spec"]["provider"]["kubernetes"]
                role_secret = tenant["roleCredentials"]
                app_secret = tenant["applicationCredentials"]
                grant = tenant["credentialReaderRole"]
                binding = tenant["credentialReaderBinding"]
                secret_name = tenant["role"]["spec"]["passwordSecret"]["name"]

                self.assertEqual(secret_name, "billing-db-auth")
                self.assertEqual(reader["metadata"]["name"], reader_name)
                self.assertEqual(generator["metadata"]["name"], "billing-generator")
                for resource in (generator, reader, role_secret, grant, binding):
                    self.assertEqual(resource["metadata"]["namespace"], "ledger")
                self.assertEqual(provider["remoteNamespace"], "ledger")
                self.assertEqual(provider["auth"]["serviceAccount"], {
                    "name": reader_name, "namespace": "ledger"
                })
                generator_ref = role_secret["spec"]["dataFrom"][0]["sourceRef"]["generatorRef"]
                self.assertEqual(generator_ref["name"], generator["metadata"]["name"])
                self.assertEqual(generator_ref["kind"], generator["kind"])
                self.assertEqual(generator_ref["apiVersion"], generator["apiVersion"])
                self.assertEqual(role_secret["spec"]["target"]["name"], secret_name)
                self.assertEqual(app_secret["metadata"]["namespace"], "payments")
                self.assertEqual(app_secret["spec"]["secretStoreRef"], {
                    "name": store["metadata"]["name"], "kind": store["kind"]
                })
                self.assertEqual(app_secret["spec"]["data"], [{
                    "secretKey": "password", "remoteRef": {"key": secret_name, "property": "password"}
                }])
                self.assertNotIn("dataFrom", app_secret["spec"])
                self.assertEqual(grant["rules"], [{
                    "apiGroups": [""], "resources": ["secrets"],
                    "resourceNames": [secret_name], "verbs": ["get"]
                }])
                self.assertEqual(binding["roleRef"], {
                    "apiGroup": "rbac.authorization.k8s.io", "kind": "Role",
                    "name": grant["metadata"]["name"]
                })
                self.assertEqual(binding["subjects"], [{
                    "kind": "ServiceAccount", "name": reader_name, "namespace": "ledger"
                }])

    def test_remote_key_reaches_external_secrets_unchanged(self):
        tenant = self.render_case("cnpg", "remote_key_flow")
        for field in ("roleCredentials", "applicationCredentials"):
            self.assertEqual(tenant[field]["spec"]["data"][0]["remoteRef"], {"key": "billing/password"})
        self.assertNotIn("credentialReaderRole", tenant)
        self.assertNotIn("credentialReaderBinding", tenant)

    def test_reader_grants_require_cross_namespace_opt_in(self):
        for case, tenant in self.render_case("cnpg", "grants_unneeded").items():
            with self.subTest(case=case):
                self.assertNotIn("credentialReaderRole", tenant)
                self.assertNotIn("credentialReaderBinding", tenant)

    def test_rejects_unrestricted_grants_and_wrong_replication_sources(self):
        self.assert_render_failure("cnpg", "unsafe_empty_grant", "at least one secret name")
        self.assert_render_failure("cnpg", "wrong_replication_source", "replicationNamespace")
