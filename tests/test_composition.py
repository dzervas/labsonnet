from support import JsonnetTestCase


class CompositionTests(JsonnetTestCase):
    def test_scalar_map_and_array_composition(self):
        app = self.render_case("composition", "composition")
        self.assertEqual(app["workload"]["spec"]["replicas"], 3)
        container = app["workload"]["spec"]["template"]["spec"]["containers"][0]
        self.assertEqual(
            {item["name"]: item["value"] for item in container["env"]},
            {"FIRST": "one", "REPLACED": "new", "SECOND": "two"},
        )
        self.assertEqual(
            [(p["name"], p["containerPort"]) for p in container["ports"]],
            [("web", 8080), ("metrics", 9090)],
        )
        self.assertEqual(
            [(p["name"], p["port"]) for p in app["service"]["spec"]["ports"]],
            [("web", 8080), ("metrics", 9090)],
        )

    def test_callbacks_resolve_each_final_identity(self):
        apps = self.render_case("composition", "reusable_callbacks")
        for name, expected in (("first", "first/one"), ("second", "second/two")):
            with self.subTest(name=name):
                container = apps[name]["workload"]["spec"]["template"]["spec"][
                    "containers"
                ][0]
                self.assertEqual(
                    container["env"], [{"name": "INSTANCE", "value": expected}]
                )

        app = self.render_case("composition", "callbackContext")
        metadata = app["workload"]["metadata"]
        self.assertEqual(
            (metadata["name"], metadata["namespace"]), ("callback-app", "callback-ns")
        )
        container = app["workload"]["spec"]["template"]["spec"]["containers"][0]
        env = {item["name"]: item["value"] for item in container["env"]}
        self.assertEqual(env["APP_NAME"], metadata["name"])
        self.assertEqual(env["APP_NAMESPACE"], metadata["namespace"])
        route = app["routing"][metadata["name"] + "-web"]["spec"]
        self.assertEqual(route["hostnames"], [metadata["name"] + ".example.test"])
        self.assertEqual(route["parentRefs"][0]["namespace"], metadata["namespace"])
