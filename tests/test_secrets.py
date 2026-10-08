from support import JsonnetTestCase


class SecretTests(JsonnetTestCase):
    def test_secret_environment_and_mounts_match_their_sources(self):
        app = self.render_case("secrets", "secretReferences")["app"]
        pod = app["workload"]["spec"]["template"]["spec"]
        container = pod["containers"][0]
        env = {
            item["name"]: item["valueFrom"]["secretKeyRef"] for item in container["env"]
        }
        self.assertEqual(
            env["EXISTING_TOKEN"], {"name": "existing-secret", "key": "token"}
        )
        resource = app["externalSecrets"]["app-secret"]
        secret = resource["spec"]
        # ExternalSecret defaults its target name to the resource name.
        target_name = secret.get("target", {}).get("name", resource["metadata"]["name"])
        self.assertEqual(env["API_TOKEN"], {"name": target_name, "key": "api-token"})
        self.assertEqual(
            secret["secretStoreRef"],
            {"name": "app-store", "kind": "ClusterSecretStore"},
        )
        self.assertEqual(secret["dataFrom"], [{"extract": {"key": "apps/secret-app"}}])

        mounts = {item["mountPath"]: item for item in container["volumeMounts"]}
        volumes = {item["name"]: item for item in pod["volumes"]}
        for path, source in (
            ("/etc/tls", "tls-secret"),
            ("/etc/app-secrets", "file-secret"),
        ):
            with self.subTest(path=path):
                mount = mounts[path]
                self.assertEqual(volumes[mount["name"]]["secret"]["secretName"], source)
                self.assertIs(mount["readOnly"], True)
        file_resource = app["externalSecrets"]["file-secret"]
        file_secret = file_resource["spec"]
        target_name = file_secret.get("target", {}).get(
            "name", file_resource["metadata"]["name"]
        )
        file_mount = mounts["/etc/app-secrets"]
        self.assertEqual(
            volumes[file_mount["name"]]["secret"]["secretName"], target_name
        )
        self.assertEqual(file_secret["secretStoreRef"]["name"], "file-store")
        self.assertEqual(file_secret["dataFrom"], [{"extract": {"key": "apps/files"}}])
