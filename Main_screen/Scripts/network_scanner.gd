extends Node

var discovered_ips: Array = []
var scan_active: bool = false

const SCAN_TIMEOUT := 2.0

func scan_network() -> Array:
	discovered_ips.clear()
	scan_active = true
	
	var local_ip = _get_local_ip()
	if local_ip == "":
		print("Could not determine local IP")
		scan_active = false
		return []
	
	var subnet = _get_subnet(local_ip)
	print("Scanning subnet: " + subnet)
	
	var socket = PacketPeerUDP.new()
	if socket.bind(9999, "0.0.0.0") != OK:
		print("Failed to bind socket")
		scan_active = false
		return []
	
	_broadcast_scan(socket, subnet)
	
	var start_time = Time.get_ticks_msec()
	while Time.get_ticks_msec() - start_time < SCAN_TIMEOUT * 1000:
		if socket.get_available_packet_count() > 0:
			var packet = socket.get_packet()
			var addr = socket.get_packet_ip()
			if not addr in discovered_ips and addr != local_ip:
				discovered_ips.append(addr)
				print("Found device: " + addr)
		await get_tree().create_timer(0.1).timeout
	
	socket.close()
	scan_active = false
	print("Scan complete. Found " + str(discovered_ips.size()) + " devices")
	return discovered_ips

func _broadcast_scan(socket: PacketPeerUDP, subnet: String) -> void:
	socket.set_broadcast_enabled(true)
	
	for i in range(1, 255):
		var target = subnet + str(i)
		socket.set_dest_address(target, 9999)
		socket.put_packet("PING".to_utf8_buffer())
	
	socket.set_broadcast_enabled(false)

func _get_local_ip() -> String:
	var ips = IP.get_local_addresses()
	for ip in ips:
		if ip.begins_with("192.168."):
			return ip
		if ip.begins_with("10."):
			return ip
		if ip.begins_with("172."):
			var parts = ip.split(".")
			if parts.size() >= 2:
				var second = int(parts[1])
				if second >= 16 and second <= 31:
					return ip
	return ""

func _get_subnet(local_ip: String) -> String:
	var parts = local_ip.split(".")
	if parts.size() >= 3:
		return parts[0] + "." + parts[1] + "." + parts[2] + "."
	return "192.168.0."

func is_scanning() -> bool:
	return scan_active
