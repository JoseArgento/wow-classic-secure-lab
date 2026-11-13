"""
Almacén La Esquina — sitio web de demostración para el lab de Blue Team.

Propósito: generar tráfico HTTP realista (normal y hostil) para validar las
detecciones del Mini SOC contra el log de acceso de nginx. NO es una app
explotable de verdad: las consultas a la base usan parámetros y la descarga
de archivos está acotada a un directorio. Lo que importa para la tesis es que
los INTENTOS queden registrados en el log con su patrón, no que el ataque
tenga éxito. Esto mantiene la red doméstica fuera de riesgo real y es un buen
punto de "gaps documentados, no escondidos".
"""
import hmac
import os
import sqlite3
from flask import (
    Flask, render_template, request, redirect, url_for,
    session, abort, send_from_directory, g,
)


def _requerido(nombre):
    """Lee una variable de entorno obligatoria; sin ella la app no arranca."""
    valor = os.environ.get(nombre, "")
    if not valor:
        raise RuntimeError(
            f"Falta la variable de entorno {nombre} (ver .env.example)"
        )
    return valor


app = Flask(__name__)
# La clave de sesión viene del entorno (.env, fuera de git) y no tiene valor
# por defecto a propósito: con una clave conocida cualquiera puede firmarse
# una cookie y entrar a /admin sin pasar por /login, es decir, sin dejar el
# 401 que mira web_login_bruteforce.
app.secret_key = _requerido("APP_SECRET")
app.config.update(
    SESSION_COOKIE_HTTPONLY=True,
    SESSION_COOKIE_SAMESITE="Lax",
    # Poner COOKIE_SECURE=1 solo cuando el sitio se sirve por HTTPS.
    SESSION_COOKIE_SECURE=os.environ.get("COOKIE_SECURE", "0") == "1",
)

DB_PATH = os.environ.get("DB_PATH", "/tmp/laesquina.db")
# Directorio del que SÍ se pueden bajar archivos (catálogos públicos).
DESCARGAS_DIR = os.path.join(app.root_path, "descargas")

# Credencial de demo. Única cuenta; la contraseña vive en .env y se le pasa
# al grupo por privado para la prueba negativa (login exitoso, no alerta).
USUARIO_DEMO = {"usuario": "admin", "password": _requerido("DEMO_PASSWORD")}

PRODUCTOS_SEED = [
    ("Yerba 1kg", "Almacén", 2800),
    ("Fideos 500g", "Almacén", 900),
    ("Aceite girasol 1.5L", "Almacén", 3200),
    ("Pan casero", "Panadería", 1500),
    ("Facturas x6", "Panadería", 2400),
    ("Gaseosa 2.25L", "Bebidas", 2600),
    ("Agua mineral 2L", "Bebidas", 1200),
    ("Detergente 750ml", "Limpieza", 1800),
]


def get_db():
    if "db" not in g:
        g.db = sqlite3.connect(DB_PATH)
        g.db.row_factory = sqlite3.Row
    return g.db


@app.teardown_appcontext
def close_db(exc):
    db = g.pop("db", None)
    if db is not None:
        db.close()


def init_db():
    # En el contenedor el catálogo ya viene creado desde el build (el
    # filesystem es de solo lectura); esto queda para correr la app suelta.
    catalogo = os.path.join(DESCARGAS_DIR, "catalogo.txt")
    if not os.path.exists(catalogo):
        os.makedirs(DESCARGAS_DIR, exist_ok=True)
        with open(catalogo, "w", encoding="utf-8") as fh:
            fh.write("Catálogo Almacén La Esquina\n")
    db = sqlite3.connect(DB_PATH)
    db.execute(
        "CREATE TABLE IF NOT EXISTS productos "
        "(id INTEGER PRIMARY KEY, nombre TEXT, categoria TEXT, precio INTEGER)"
    )
    if db.execute("SELECT COUNT(*) FROM productos").fetchone()[0] == 0:
        db.executemany(
            "INSERT INTO productos (nombre, categoria, precio) VALUES (?, ?, ?)",
            PRODUCTOS_SEED,
        )
    db.commit()
    db.close()


@app.route("/")
def index():
    return render_template("index.html")


@app.route("/productos")
def productos():
    # El buscador recibe ?q=. Usamos consulta PARAMETRIZADA: aunque llegue
    # un payload de SQLi, no se inyecta nada. El intento igual queda en el
    # log de nginx (que es lo que detecta la regla web_sqli_attempt).
    q = request.args.get("q", "").strip()
    db = get_db()
    if q:
        filas = db.execute(
            "SELECT nombre, categoria, precio FROM productos "
            "WHERE nombre LIKE ? ORDER BY nombre",
            (f"%{q}%",),
        ).fetchall()
    else:
        filas = db.execute(
            "SELECT nombre, categoria, precio FROM productos ORDER BY nombre"
        ).fetchall()
    return render_template("productos.html", productos=filas, q=q)


@app.route("/login", methods=["GET", "POST"])
def login():
    if request.method == "POST":
        usuario = request.form.get("usuario", "")
        password = request.form.get("password", "")
        clave_ok = hmac.compare_digest(
            password.encode(), USUARIO_DEMO["password"].encode()
        )
        if usuario == USUARIO_DEMO["usuario"] and clave_ok:
            session["usuario"] = usuario
            return redirect(url_for("admin"))
        # Credenciales inválidas -> 401. Esta es la señal de web_login_bruteforce.
        return render_template("login.html", error=True), 401
    return render_template("login.html", error=False)


@app.route("/logout")
def logout():
    session.clear()
    return redirect(url_for("index"))


@app.route("/admin")
def admin():
    if "usuario" not in session:
        # Sin sesión -> redirección al login (302), no 200.
        return redirect(url_for("login"))
    return render_template("admin.html", usuario=session["usuario"])


@app.route("/descargas")
def descargas():
    # Descarga acotada al directorio DESCARGAS_DIR. send_from_directory
    # rechaza el path traversal y devuelve 404, pero el intento ya quedó
    # en el log (web_path_traversal).
    archivo = request.args.get("file", "catalogo.txt")
    try:
        return send_from_directory(DESCARGAS_DIR, archivo, as_attachment=True)
    except Exception:
        abort(404)


@app.errorhandler(404)
def no_encontrado(e):
    return render_template("404.html"), 404


# Inicializa la base al importar (gunicorn no corre __main__).
init_db()

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8000)
