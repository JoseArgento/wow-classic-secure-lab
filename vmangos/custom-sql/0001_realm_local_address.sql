-- Va en ~/vmangos-deploy/storage/database/custom-sql/ en el i3.
-- vmangos-deploy procesa esta carpeta en cada arranque de la base, en orden
-- alfabético; por eso el SQL tiene que ser idempotente.
--
-- Split horizon para el realm: los clientes de la LAN reciben la IP local
-- del i3 y el resto, la dirección pública (VMANGOS_REALMLIST_ADDRESS).
-- Sin esto, un cliente de la LAN se loguea en realmd con su IP local pero
-- llega a mangosd por NAT loopback con la IP pública, y mangosd lo corta
-- ("Account IP differs from realmd"). El realmd resuelve el nombre DDNS del
-- lado del servidor, así que un archivo hosts en el cliente no alcanza.
UPDATE realmd.realmlist
SET localAddress = '192.168.1.66', localSubnetMask = '255.255.255.0'
WHERE id = 1;
