Workflows exportados con el CLI de n8n (`n8n export:workflow --separate`).
Se importan con `n8n import:workflow --separate --input=<carpeta>`.

Las credenciales NO están acá: el export guarda solo su id y nombre. En una
instalación nueva hay que crearlas a mano con los mismos nombres (ver
../README.md) y reasignarlas en cada nodo.
