FROM python:3.13-slim

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

# El catálogo se crea acá: en ejecución el filesystem es de solo lectura.
# Usuario sin privilegios, y el código queda de root (la app no puede pisarse).
RUN mkdir -p descargas \
 && printf 'Catálogo Almacén La Esquina\n' > descargas/catalogo.txt \
 && useradd -m appuser
USER appuser

ENV DB_PATH=/tmp/laesquina.db \
    PYTHONDONTWRITEBYTECODE=1
EXPOSE 8000

# 2 workers alcanza de sobra para el lab. Sin access log de gunicorn: el log
# de acceso es el de nginx (la fuente del Mini SOC); los errores van a stderr.
# Sin socket de control: no se usa y gunicorn lo querría escribir en el home.
CMD ["gunicorn", "--bind", "0.0.0.0:8000", "--workers", "2", "--no-control-socket", "app:app"]
