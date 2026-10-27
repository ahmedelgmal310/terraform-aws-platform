# Nothing may be reachable from the internet except HTTP(S), administrative
# ports are never exposed, and databases are never public.
package terraform.network

import data.terraform.lib

world_v4 := "0.0.0.0/0"

world_v6 := "::/0"

admin_ports := {22, 3389}

web_ports := {80, 443}

# Standalone rule resources (aws_vpc_security_group_ingress_rule).
deny contains msg if {
	some rule in lib.changes_of("aws_vpc_security_group_ingress_rule")
	after := lib.after(rule)
	open_to_world(after.cidr_ipv4, after.cidr_ipv6)
	some port in admin_ports
	covers(after.ip_protocol, after.from_port, after.to_port, port)
	msg := sprintf("%s: port %d must not be open to the internet", [rule.address, port])
}

deny contains msg if {
	some rule in lib.changes_of("aws_vpc_security_group_ingress_rule")
	after := lib.after(rule)
	open_to_world(after.cidr_ipv4, after.cidr_ipv6)
	not web_only(after.ip_protocol, after.from_port, after.to_port)
	msg := sprintf("%s: only ports 80 and 443 may be open to the internet", [rule.address])
}

# Legacy aws_security_group_rule.
deny contains msg if {
	some rule in lib.changes_of("aws_security_group_rule")
	after := lib.after(rule)
	after.type == "ingress"
	some cidr in array.concat(lib.list_or_empty(object.get(after, "cidr_blocks", [])), lib.list_or_empty(object.get(after, "ipv6_cidr_blocks", [])))
	cidr in {world_v4, world_v6}
	not web_only(after.protocol, after.from_port, after.to_port)
	msg := sprintf("%s: only ports 80 and 443 may be open to the internet", [rule.address])
}

# Inline ingress blocks on aws_security_group.
deny contains msg if {
	some sg in lib.changes_of("aws_security_group")
	some ingress in lib.list_or_empty(object.get(lib.after(sg), "ingress", []))
	some cidr in array.concat(lib.list_or_empty(object.get(ingress, "cidr_blocks", [])), lib.list_or_empty(object.get(ingress, "ipv6_cidr_blocks", [])))
	cidr in {world_v4, world_v6}
	not web_only(ingress.protocol, ingress.from_port, ingress.to_port)
	msg := sprintf("%s: inline ingress opens ports %d-%d to the internet", [sg.address, ingress.from_port, ingress.to_port])
}

deny contains msg if {
	some db in lib.changes_of("aws_db_instance")
	lib.after(db).publicly_accessible == true
	msg := sprintf("%s: RDS instance must not be publicly accessible", [db.address])
}

deny contains msg if {
	some subnet in lib.changes_of("aws_subnet")
	lib.after(subnet).map_public_ip_on_launch == true
	msg := sprintf("%s: subnets must not auto-assign public IPs", [subnet.address])
}

deny contains msg if {
	some svc in lib.changes_of("aws_ecs_service")
	some net in lib.after(svc).network_configuration
	net.assign_public_ip == true
	msg := sprintf("%s: ECS tasks must not get public IPs", [svc.address])
}

open_to_world(v4, _) if v4 == world_v4

open_to_world(_, v6) if v6 == world_v6

all_protocols(p) if p in {"-1", "all"}

covers(protocol, _, _, _) if all_protocols(protocol)

covers(protocol, from, to, port) if {
	not all_protocols(protocol)
	from <= port
	port <= to
}

web_only(protocol, from, to) if {
	not all_protocols(protocol)
	from == to
	from in web_ports
}
