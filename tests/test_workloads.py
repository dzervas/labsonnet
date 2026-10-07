from support import JsonnetTestCase


class WorkloadTests(JsonnetTestCase):
    def test_pod_labels_preserve_workload_and_service_selectors(self):
        for name in ("labeled_deployment", "labeled_statefulset"):
            with self.subTest(name=name):
                app = self.render_case("workloads", name)
                spec = app["workload"]["spec"]
                labels = spec["template"]["metadata"]["labels"]
                self.assertEqual(labels["team"], "platform")
                selectors = [
                    spec["selector"]["matchLabels"],
                    app["service"]["spec"]["selector"],
                ]
                if name == "labeled_statefulset":
                    selectors.append(app["headlessService"]["spec"]["selector"])
                for selector in selectors:
                    self.assertTrue(selector)
                    for key, value in selector.items():
                        self.assertEqual(labels[key], value)
        for name in (
            "invalid_identity_label",
            "invalid_generated_label",
            "invalid_statefulset_label",
        ):
            with self.subTest(name=name):
                self.assert_render_failure(
                    "workloads", name, "pod labels must not override selector labels"
                )

    def test_security_defaults_and_explicit_null_removal(self):
        app = self.render_case("workloads", "security_defaults")
        pod = app["workload"]["spec"]["template"]["spec"]
        context = pod["containers"][0]["securityContext"]
        self.assertIs(context["runAsNonRoot"], True)
        self.assertIs(context["allowPrivilegeEscalation"], False)
        self.assertEqual(context["capabilities"]["drop"], ["ALL"])
        self.assertEqual(pod["securityContext"]["fsGroup"], context["runAsUser"])

        app = self.render_case("workloads", "security_overrides")
        context = app["workload"]["spec"]["template"]["spec"]["securityContext"]
        self.assertNotIn("fsGroup", context)
        self.assertNotIn("fsGroupChangePolicy", context)
        self.assertIs(context["runAsNonRoot"], False)
        self.assertEqual(context["runAsUser"], 0)
        self.assertEqual(context["supplementalGroups"], [])
