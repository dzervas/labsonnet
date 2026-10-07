from support import JsonnetTestCase


def _named(test_case, items, name):
    matches = [item for item in items if item.get("name") == name]
    test_case.assertEqual(len(matches), 1, f"expected one item named {name!r}")
    return matches[0]


def _mount_at(test_case, mounts, path):
    matches = [mount for mount in mounts if mount.get("mountPath") == path]
    test_case.assertEqual(len(matches), 1, f"expected one mount at {path!r}")
    return matches[0]


def _claim_template_named(test_case, claims, name):
    matches = [
        claim for claim in claims if claim.get("metadata", {}).get("name") == name
    ]
    test_case.assertEqual(
        len(matches), 1, f"expected one claim template named {name!r}"
    )
    return matches[0]


class StorageTests(JsonnetTestCase):
    def test_stateful_claim_and_image_volume_mounts_match_the_workload(self):
        rendered = self.render_case("storage", "stateful_pv")
        workload = rendered["workload"]
        pod = workload["spec"]["template"]["spec"]

        self.assertEqual(workload["kind"], "StatefulSet")
        headless = rendered["headlessService"]
        self.assertEqual(workload["spec"]["serviceName"], headless["metadata"]["name"])
        self.assertEqual(headless["spec"]["clusterIP"], "None")

        claims = workload["spec"]["volumeClaimTemplates"]
        self.assertEqual(len(claims), 1)
        claim = _claim_template_named(self, claims, "database-data")
        self.assertIsNone(rendered["pvc"])
        self.assertNotIn(
            claim["metadata"]["name"], [volume["name"] for volume in pod["volumes"]]
        )
        self.assertEqual(claim["spec"]["resources"]["requests"]["storage"], "8Gi")
        self.assertEqual(claim["spec"]["storageClassName"], "fast")

        image_volume = _named(self, pod["volumes"], "extensions")
        self.assertEqual(
            image_volume["image"]["reference"],
            "registry.example/postgres-extensions:18",
        )
        self.assertEqual(image_volume["image"]["pullPolicy"], "Never")
        mounts = pod["containers"][0]["volumeMounts"]
        data_mount = _mount_at(self, mounts, "/var/lib/database")
        self.assertEqual(data_mount["name"], "database-data")
        self.assertFalse(data_mount.get("readOnly", False))
        extension_mount = _mount_at(self, mounts, "/usr/share/postgresql/extensions")
        self.assertEqual(extension_mount["name"], "extensions")
        self.assertTrue(extension_mount["readOnly"])

    def test_equal_claim_templates_deduplicate_and_allow_distinct_subpath_mounts(self):
        rendered = self.render_case("storage", "stateful_claim_template_mounts")
        workload = rendered["workload"]
        pod = workload["spec"]["template"]["spec"]

        self.assertEqual(workload["kind"], "StatefulSet")
        claims = workload["spec"]["volumeClaimTemplates"]
        self.assertEqual(len(claims), 1)
        self.assertEqual(pod["volumes"], [])
        self.assertEqual(
            _claim_template_named(self, claims, "state")["spec"]["resources"][
                "requests"
            ]["storage"],
            "2Gi",
        )

        mounts = pod["containers"][0]["volumeMounts"]
        config_mount = _mount_at(self, mounts, "/config")
        data_mount = _mount_at(self, mounts, "/data")
        self.assertEqual(
            (config_mount["name"], config_mount["subPath"]), ("state", "config")
        )
        self.assertEqual((data_mount["name"], data_mount["subPath"]), ("state", "data"))

    def test_existing_pvc_is_declared_once_and_shared_across_mounts(self):
        rendered = self.render_case("storage", "existing_pvc_multiple_mounts")
        pod = rendered["workload"]["spec"]["template"]["spec"]

        volume = _named(self, pod["volumes"], "media")
        self.assertEqual(
            volume["persistentVolumeClaim"]["claimName"],
            "shared-media.claim",
        )
        mounts = pod["containers"][0]["volumeMounts"]
        self.assertEqual(sum(mount["name"] == "media" for mount in mounts), 3)
        incoming = _mount_at(self, mounts, "/incoming")
        movies = _mount_at(self, mounts, "/movies")
        series = _mount_at(self, mounts, "/series")
        self.assertEqual(incoming["name"], "media")
        self.assertFalse(incoming.get("readOnly", False))
        for mount, sub_path in ((movies, "movies"), (series, "series")):
            self.assertEqual(mount["name"], "media")
            self.assertTrue(mount["readOnly"])
            self.assertEqual(mount["subPath"], sub_path)

    def test_identical_image_volume_declarations_deduplicate(self):
        rendered = self.render_case("storage", "duplicate_image_volume")
        pod = rendered["workload"]["spec"]["template"]["spec"]

        self.assertEqual(
            sum(volume["name"] == "extensions" for volume in pod["volumes"]), 1
        )
        image_volume = _named(self, pod["volumes"], "extensions")
        self.assertEqual(
            image_volume["image"]["reference"], "registry.example/extensions:v1"
        )
        self.assertEqual(image_volume["image"]["pullPolicy"], "IfNotPresent")
        mount = _mount_at(self, pod["containers"][0]["volumeMounts"], "/opt/extensions")
        self.assertEqual(mount["name"], "extensions")
        self.assertTrue(mount["readOnly"])

    def test_mount_resolves_a_volume_declared_later(self):
        rendered = self.render_case("storage", "volume_declared_after_mount")
        pod = rendered["workload"]["spec"]["template"]["spec"]

        volume = _named(self, pod["volumes"], "extensions")
        self.assertEqual(volume["image"]["reference"], "registry.example/extensions:v1")
        mount = _mount_at(self, pod["containers"][0]["volumeMounts"], "/opt/extensions")
        self.assertEqual(mount["name"], "extensions")
        self.assertTrue(mount["readOnly"])

    def test_invalid_storage_relationships_fail_with_specific_diagnostics(self):
        cases = (
            (
                "conflicting_volume_definitions",
                "conflicting definitions for volume 'shared'",
            ),
            (
                "deployment_managed_pv",
                "managed claim templates require StatefulSet type",
            ),
            (
                "unknown_volume_reference",
                "unknown volume mount references: missing-volume",
            ),
            ("duplicate_mount_path", "duplicate volume mount paths"),
            ("duplicate_secret_and_volume_mount_path", "duplicate volume mount paths"),
            (
                "writable_image_volume_mount",
                "image volume mounts must set readOnly=true",
            ),
        )
        for case_name, diagnostic in cases:
            with self.subTest(case=case_name):
                self.assert_render_failure("storage", case_name, diagnostic)
