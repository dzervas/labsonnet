from support import JsonnetTestCase


class RoutingTests(JsonnetTestCase):
    def test_routes_share_ports_and_reference_the_service(self):
        app = self.render_case("routing", "routes")
        service = app["service"]
        service_ports = service["spec"]["ports"]
        container_ports = app["workload"]["spec"]["template"]["spec"]["containers"][0][
            "ports"
        ]
        expected_ports = {8080, 5353, 50051, 5432}
        self.assertEqual({p["port"] for p in service_ports}, expected_ports)
        self.assertEqual({p["containerPort"] for p in container_ports}, expected_ports)
        self.assertEqual(len(service_ports), len(expected_ports))
        self.assertEqual(len(container_ports), len(expected_ports))
        cases = (
            ("public", "HTTPRoute", 8080, "public-gateway", "network", "https"),
            ("private", "HTTPRoute", 8080, "private-gateway", "vpn", "https"),
            ("dns", "UDPRoute", 5353, "dns-gateway", "network", "dns"),
            ("grpc", "GRPCRoute", 50051, "public-gateway", "network", "https"),
            ("database", "TCPRoute", 5432, "public-gateway", "network", "postgres"),
        )
        for name, kind, port, gateway, namespace, section in cases:
            with self.subTest(route=name):
                route = app["routing"][name]
                self.assertEqual(route["kind"], kind)
                backend = route["spec"]["rules"][0]["backendRefs"][0]
                self.assertEqual(
                    (backend["name"], backend["port"]),
                    (service["metadata"]["name"], port),
                )
                self.assertEqual(
                    route["spec"]["parentRefs"],
                    [{"name": gateway, "namespace": namespace, "sectionName": section}],
                )
                protocol = "UDP" if kind == "UDPRoute" else "TCP"
                self.assertEqual(
                    next(p for p in service_ports if p["port"] == port)["protocol"],
                    protocol,
                )
                self.assertEqual(
                    next(p for p in container_ports if p["containerPort"] == port)[
                        "protocol"
                    ],
                    protocol,
                )
        self.assertEqual(
            app["routing"]["public"]["spec"]["hostnames"], ["default.example.test"]
        )
        self.assertEqual(
            app["routing"]["private"]["spec"]["hostnames"], ["private.example.test"]
        )

    def test_ordinary_and_headless_exposure_are_independent(self):
        app = self.render_case("routing", "separate_exposure")
        self.assertEqual(
            [(p["name"], p["port"]) for p in app["service"]["spec"]["ports"]],
            [("web", 8080)],
        )
        headless = app["headlessService"]
        self.assertEqual(
            [(p["name"], p["port"]) for p in headless["spec"]["ports"]],
            [("peer", 5432)],
        )
        self.assertEqual(
            app["workload"]["spec"]["serviceName"], headless["metadata"]["name"]
        )
        self.assertFalse(headless["spec"].get("publishNotReadyAddresses", False))
        ports = app["workload"]["spec"]["template"]["spec"]["containers"][0]["ports"]
        self.assertEqual({p["containerPort"] for p in ports}, {8080, 5432})

    def test_monitor_references_the_final_ordinary_service(self):
        app = self.render_case("routing", "valid_monitor")
        service = app["service"]
        monitor = app["monitors"]["web"]["spec"]
        self.assertEqual(len(service["spec"]["ports"]), 1)
        self.assertEqual(
            monitor["endpoints"][0]["port"], service["spec"]["ports"][0]["name"]
        )
        selector = monitor["selector"]["matchLabels"]
        self.assertTrue(selector)
        for key, value in selector.items():
            self.assertEqual(service["metadata"]["labels"][key], value)
        for name in ("discarded_alias_monitor", "headless_only_monitor"):
            with self.subTest(name=name):
                self.assert_render_failure(
                    "routing",
                    name,
                    "serviceMonitor must reference a port exposed by the ordinary Service",
                )

    def test_conflicting_routing_configuration_fails(self):
        for name, diagnostic in (
            ("invalidMultipleRoutingTypes", "at most one routing type"),
            ("invalidProtocolConflict", "explicit 'protocol' conflicts"),
        ):
            with self.subTest(name=name):
                self.assert_render_failure("routing", name, diagnostic)
