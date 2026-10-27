package terraform.network_test

import data.terraform.network

rc(type, after) := {
	"address": concat(".", [type, "this"]),
	"mode": "managed",
	"type": type,
	"change": {"actions": ["create"], "after": after, "after_unknown": {}},
}

ingress(cidr, protocol, from, to) := rc("aws_vpc_security_group_ingress_rule", {
	"cidr_ipv4": cidr, "cidr_ipv6": null,
	"ip_protocol": protocol, "from_port": from, "to_port": to,
})

test_ssh_from_world_denied if {
	some msg in network.deny with input as {"resource_changes": [ingress("0.0.0.0/0", "tcp", 22, 22)]}
	contains(msg, "port 22")
}

test_port_range_covering_rdp_denied if {
	some msg in network.deny with input as {"resource_changes": [ingress("0.0.0.0/0", "tcp", 3000, 4000)]}
	contains(msg, "port 3389")
}

test_all_protocols_from_world_denied if {
	some msg in network.deny with input as {"resource_changes": [ingress("0.0.0.0/0", "-1", null, null)]}
	contains(msg, "port 22")
}

test_ipv6_world_denied if {
	rule := rc("aws_vpc_security_group_ingress_rule", {"cidr_ipv4": null, "cidr_ipv6": "::/0", "ip_protocol": "tcp", "from_port": 22, "to_port": 22})
	some msg in network.deny with input as {"resource_changes": [rule]}
	contains(msg, "port 22")
}

test_https_from_world_allowed if {
	count(network.deny) == 0 with input as {"resource_changes": [ingress("0.0.0.0/0", "tcp", 443, 443)]}
}

test_postgres_from_world_denied if {
	some msg in network.deny with input as {"resource_changes": [ingress("0.0.0.0/0", "tcp", 5432, 5432)]}
	contains(msg, "only ports 80 and 443")
}

test_ssh_from_private_range_allowed if {
	count(network.deny) == 0 with input as {"resource_changes": [ingress("10.0.0.0/8", "tcp", 22, 22)]}
}

test_legacy_rule_denied if {
	rule := rc("aws_security_group_rule", {"type": "ingress", "cidr_blocks": ["0.0.0.0/0"], "ipv6_cidr_blocks": null, "protocol": "tcp", "from_port": 22, "to_port": 22})
	some msg in network.deny with input as {"resource_changes": [rule]}
	contains(msg, "only ports 80 and 443")
}

test_inline_ingress_denied if {
	sg := rc("aws_security_group", {"ingress": [{"cidr_blocks": ["0.0.0.0/0"], "ipv6_cidr_blocks": [], "protocol": "tcp", "from_port": 22, "to_port": 22}]})
	some msg in network.deny with input as {"resource_changes": [sg]}
	contains(msg, "inline ingress")
}

test_public_rds_denied if {
	db := rc("aws_db_instance", {"publicly_accessible": true})
	some msg in network.deny with input as {"resource_changes": [db]}
	contains(msg, "publicly accessible")
}

test_public_ip_subnet_denied if {
	subnet := rc("aws_subnet", {"map_public_ip_on_launch": true})
	some msg in network.deny with input as {"resource_changes": [subnet]}
	contains(msg, "auto-assign")
}

test_ecs_public_ip_denied if {
	svc := rc("aws_ecs_service", {"network_configuration": [{"assign_public_ip": true}]})
	some msg in network.deny with input as {"resource_changes": [svc]}
	contains(msg, "public IPs")
}
