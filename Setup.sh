#!/bin/bash

# Krev root
if [ "$(id -u)" -ne 0 ]; then
    echo "Error: Run this script as root."
    echo "  sudo bash Setup.sh"
    exit 1
fi

echo "=============================="
echo "   Web Server Setup Script"
echo "=============================="

# Spør etter ny system-bruker
read -p "Enter username for new server user: " NEW_USER
if [ -z "$NEW_USER" ]; then
  echo "Error: Username cannot be empty!"
  exit 1
fi

read -sp "Enter password for $NEW_USER: " NEW_USER_PASS
echo
if [ -z "$NEW_USER_PASS" ]; then
  echo "Error: Password cannot be empty!"
  exit 1
fi

# Spør etter prosjektnavn / domain
read -p "Enter your project name / domain (e.g. myapp): " DOMAIN

if [ -z "$DOMAIN" ]; then
  echo "Error: Domain cannot be empty!"
  exit 1
fi

read -p "Enter MySQL root password: " MYSQL_ROOT_PASS
read -p "Enter a name for the Flask DB user: " DB_USER
read -p "Enter password for Flask DB user: " DB_PASS

echo ""
echo "New user: $NEW_USER"
echo "Project:  $DOMAIN"
echo ""

# ─── 1. Oppdater system ───────────────────────────────────────────────────────
echo "[1/10] Updating system..."
apt update && apt upgrade -y

# ─── 2. Lag system-bruker ────────────────────────────────────────────────────
echo "[2/10] Creating system user '$NEW_USER'..."
if id "$NEW_USER" &>/dev/null; then
    echo "  User $NEW_USER already exists, skipping."
else
    useradd -m -s /bin/bash "$NEW_USER"
    printf '%s:%s\n' "$NEW_USER" "$NEW_USER_PASS" | chpasswd
    usermod -aG sudo "$NEW_USER"
    echo "  User $NEW_USER created and added to sudo group."
fi

# ─── 3. Installer LAMP + Python + WSGI ───────────────────────────────────────
echo "[3/10] Installing LAMP + Python3 + WSGI..."
apt install -y \
  apache2 \
  mysql-server \
  php libapache2-mod-php php-mysql \
  python3 python3-pip python3-venv \
  libapache2-mod-wsgi-py3

a2enmod wsgi

# ─── 4. Lag web-mappe og virtualenv ──────────────────────────────────────────
echo "[4/10] Creating project directory and virtualenv..."
PYTHON_VERSION=$(python3 -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")
mkdir -p /var/www/$DOMAIN
chown -R $NEW_USER:www-data /var/www/$DOMAIN
chmod -R 755 /var/www/$DOMAIN

cd /var/www/$DOMAIN
python3 -m venv env
source env/bin/activate

pip install --upgrade pip
pip install flask mysql-connector-python flask-wtf werkzeug

deactivate

# ─── 5. MySQL: sikre og konfigurer database ─────────────────────────────────
echo "[5/10] Configuring MySQL database..."
systemctl start mysql

# Sett root-passord og sikre installasjonen (erstatter mysql_secure_installation)
mysql -u root <<SQLSECURE
ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '$MYSQL_ROOT_PASS';
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test_%';
FLUSH PRIVILEGES;
SQLSECURE

mysql -u root -p"$MYSQL_ROOT_PASS" <<SQL
CREATE DATABASE IF NOT EXISTS ${DOMAIN//-/_}_db;
CREATE USER IF NOT EXISTS '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';
GRANT ALL PRIVILEGES ON ${DOMAIN//-/_}_db.* TO '$DB_USER'@'localhost';
FLUSH PRIVILEGES;
USE ${DOMAIN//-/_}_db;
CREATE TABLE IF NOT EXISTS brukere (
    bruker_id INT PRIMARY KEY AUTO_INCREMENT,
    navn VARCHAR(255),
    brukernavn VARCHAR(255) UNIQUE,
    passord VARCHAR(255),
    adresse VARCHAR(255)
);
SQL

DB_NAME="${DOMAIN//-/_}_db"

# ─── 6. Lag app.py ────────────────────────────────────────────────────────────
echo "[6/10] Creating app.py..."
cat > /var/www/$DOMAIN/app.py <<PYEOF
from flask import Flask, render_template, redirect, session
from forms import RegisterForm, LoginForm
import mysql.connector
from werkzeug.security import generate_password_hash, check_password_hash

app = Flask(__name__)
app.secret_key = "hemmelig-nok"

def get_conn():
    return mysql.connector.connect(
        host="localhost",
        user="$DB_USER",
        password="$DB_PASS",
        database="$DB_NAME"
    )

@app.route("/")
def index():
    return render_template("index.html")

@app.route("/register", methods=["GET", "POST"])
def register():
    form = RegisterForm()
    if form.validate_on_submit():
        navn = form.name.data
        brukernavn = form.username.data
        passord_hash = generate_password_hash(form.password.data)
        adresse = form.address.data

        conn = get_conn()
        cur = conn.cursor()
        try:
            cur.execute(
                "INSERT INTO brukere (navn, brukernavn, passord, adresse) VALUES (%s, %s, %s, %s)",
                (navn, brukernavn, passord_hash, adresse)
            )
            conn.commit()
            return redirect("/login")
        except mysql.connector.IntegrityError:
            form.username.errors.append("Brukernavnet er allerede i bruk")
        finally:
            cur.close()
            conn.close()

    return render_template("register.html", form=form)

@app.route("/login", methods=["GET", "POST"])
def login():
    form = LoginForm()
    if form.validate_on_submit():
        brukernavn = form.username.data
        passord = form.password.data

        conn = get_conn()
        cur = conn.cursor()
        cur.execute(
            "SELECT navn, passord FROM brukere WHERE brukernavn=%s",
            (brukernavn,)
        )
        user = cur.fetchone()
        cur.close()
        conn.close()

        if user:
            passord_db = user[1]
            if check_password_hash(passord_db, passord):
                session["navn"] = user[0]
                return redirect("/welcome")
        form.username.errors.append("Feil brukernavn eller passord")

    return render_template("login.html", form=form)

@app.route("/welcome")
def welcome():
    navn = session.get("navn")
    if not navn:
        return redirect("/login")
    return render_template("welcome.html", name=navn)

if __name__ == "__main__":
    app.run()
PYEOF

# ─── 7. Lag forms.py ──────────────────────────────────────────────────────────
echo "[7/10] Creating forms.py..."
cat > /var/www/$DOMAIN/forms.py <<PYEOF
from flask_wtf import FlaskForm
from wtforms import StringField, PasswordField, SubmitField
from wtforms.validators import InputRequired

class RegisterForm(FlaskForm):
    username = StringField("Brukernavn", validators=[InputRequired()])
    password = PasswordField("Passord", validators=[InputRequired()])
    name = StringField("Navn", validators=[InputRequired()])
    address = StringField("Adresse", validators=[InputRequired()])
    submit = SubmitField("Registrer")

class LoginForm(FlaskForm):
    username = StringField("Brukernavn", validators=[InputRequired()])
    password = PasswordField("Passord", validators=[InputRequired()])
    submit = SubmitField("Logg inn")
PYEOF

# ─── 8. Lag HTML templates ────────────────────────────────────────────────────
echo "[8/10] Creating HTML templates..."
mkdir -p /var/www/$DOMAIN/templates

cat > /var/www/$DOMAIN/templates/base.html <<'HTML'
<!DOCTYPE html>
<html>
<head>
    <title>Flask + MySQL Demo</title>
</head>
<body>
    <h1>Flask + MySQL Demo</h1>
    <hr>
    {% block content %}{% endblock %}
</body>
</html>
HTML

cat > /var/www/$DOMAIN/templates/index.html <<'HTML'
{% extends "base.html" %}

{% block content %}
<p><a href="{{ url_for('register') }}">Registrer ny bruker</a></p>
<p><a href="{{ url_for('login') }}">Logg inn</a></p>
{% endblock %}
HTML

cat > /var/www/$DOMAIN/templates/register.html <<'HTML'
{% extends "base.html" %}

{% block content %}
<h2>Registrer ny bruker</h2>
<form method="POST">
    {{ form.hidden_tag() }}
    {{ form.name.label }} {{ form.name }}<br>
    {{ form.username.label }} {{ form.username }}<br>
    {{ form.password.label }} {{ form.password }}<br>
    {{ form.address.label }} {{ form.address }}<br>
    {{ form.submit }}
</form>
{% endblock %}
HTML

cat > /var/www/$DOMAIN/templates/login.html <<'HTML'
{% extends "base.html" %}

{% block content %}
<h2>Logg inn</h2>
<form method="POST">
    {{ form.hidden_tag() }}
    {{ form.username.label }} {{ form.username }}<br>
    {{ form.password.label }} {{ form.password }}<br>
    {% for error in form.username.errors %}
        <p style="color:red">{{ error }}</p>
    {% endfor %}
    {{ form.submit }}
</form>
{% endblock %}
HTML

cat > /var/www/$DOMAIN/templates/welcome.html <<'HTML'
{% extends "base.html" %}

{% block content %}
<h2>Velkommen, {{ name }}!</h2>
<p>Du er nå logget inn.</p>
<a href="/">Tilbake til startsiden</a>
{% endblock %}
HTML

# ─── 9. Lag app.wsgi ──────────────────────────────────────────────────────────
echo "[9/10] Creating app.wsgi..."
cat > /var/www/$DOMAIN/app.wsgi <<WSGIEOF
import sys
import site
import os

site.addsitedir('/var/www/$DOMAIN/env/lib/python$PYTHON_VERSION/site-packages')

sys.path.insert(0, '/var/www/$DOMAIN')

os.chdir('/var/www/$DOMAIN')

os.environ['VIRTUAL_ENV'] = '/var/www/$DOMAIN/env'
os.environ['PATH'] = '/var/www/$DOMAIN/env/bin:' + os.environ['PATH']

from app import app as application
WSGIEOF

# ─── 10. Apache VirtualHost med WSGI ────────────────────────────────────────
echo "[10/10] Creating Apache VirtualHost with WSGI..."

cat > /etc/apache2/sites-available/$DOMAIN.conf <<EOL
<VirtualHost *:80>
    ServerName $DOMAIN
    ServerAlias www.$DOMAIN
    ServerAdmin webmaster@$DOMAIN

    WSGIDaemonProcess $DOMAIN python-home=/var/www/$DOMAIN/env python-path=/var/www/$DOMAIN
    WSGIProcessGroup $DOMAIN
    WSGIScriptAlias / /var/www/$DOMAIN/app.wsgi

    <Directory /var/www/$DOMAIN>
        Require all granted
        Options FollowSymLinks
    </Directory>

    ErrorLog \${APACHE_LOG_DIR}/$DOMAIN-error.log
    CustomLog \${APACHE_LOG_DIR}/$DOMAIN-access.log combined
</VirtualHost>
EOL

# Sett fil-rettigheter
find /var/www/$DOMAIN -type d -exec chmod 755 {} \;
find /var/www/$DOMAIN -type f -exec chmod 644 {} \;
chmod -R g+rx /var/www/$DOMAIN/env

# Aktiver site og restart Apache
a2dissite 000-default.conf 2>/dev/null || true
a2ensite $DOMAIN.conf
apache2ctl configtest
systemctl restart apache2

# Brannmur
ufw allow 'Apache'
ufw --force enable

SERVER_IP=$(hostname -I | awk '{print $1}')

echo ""
echo "======================================="
echo " Setup Complete!"
echo "---------------------------------------"
echo " New user:  $NEW_USER"
echo " Project:   $DOMAIN"
echo " Web root:  /var/www/$DOMAIN"
echo " Database:  $DB_NAME"
echo " DB user:   $DB_USER"
echo " Python:    $PYTHON_VERSION"
echo "---------------------------------------"
echo " Visit:     http://$SERVER_IP"
echo " SSH:       ssh $NEW_USER@$SERVER_IP"
echo "======================================="