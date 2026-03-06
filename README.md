# LAMP + Flask Login Setup Script

Et automatisert Bash-script som setter opp en komplett webserver med LAMP, Flask og en ferdig login-side med hashed passord.

---

## Hva scriptet gjør

1. **Oppdaterer systemet** – `apt update && apt upgrade`
2. **Installerer LAMP + Python + WSGI**
   - Apache2, MySQL, PHP
   - Python 3, pip, virtualenv (`python3.13-venv`)
   - `libapache2-mod-wsgi-py3`
3. **Lager prosjektmappe** `/var/www/<prosjektnavn>` med riktige rettigheter
4. **Setter opp virtualenv** og installerer:
   - Flask, Flask-WTF, mysql-connector-python, Werkzeug
5. **Konfigurerer MySQL** – starter tjenesten, lager database og tabell (`brukere`)
6. **Lager `app.py`** med disse rutene:
   - `/` – Forside med lenker til registrer/logg inn
   - `/register` – Registrer ny bruker (passord lagres hashet)
   - `/login` – Logg inn (passord sjekkes mot hash i databasen)
   - `/welcome` – Velkomstside for innloggede brukere
7. **Lager `forms.py`** med `RegisterForm` og `LoginForm` (Flask-WTF)
8. **Lager HTML-templates**: `base.html`, `index.html`, `register.html`, `login.html`, `welcome.html`
9. **Lager `app.wsgi`** som kobler Flask-appen til Apache via WSGI
10. **Konfigurerer Apache VirtualHost** med WSGI og aktiverer siden
11. **Setter rettigheter** – mapper: 755, filer: 644, env: g+rx
12. **Åpner brannmur** for Apache med UFW og restarter Apache

---

## Krav

- Ubuntu/Debian-basert server
- `sudo`-tilgang
- Internett-tilgang for pakkeinstallasjon

---

## Bruk

### 1. Klon repoet (eller kopier scriptet til serveren)

```bash
git clone https://github.com/USERNAME/REPO.git
cd REPO
```

Eller kjør direkte fra GitHub:

```bash
curl -s https://raw.githubusercontent.com/USERNAME/REPO/main/Setup.sh | bash
```

### 2. Gi scriptet kjøretillatelse

```bash
chmod +x Setup.sh
```

### 3. Kjør scriptet

```bash
./Setup.sh
```

### 4. Svar på spørsmålene

Scriptet spør om følgende ved oppstart:

| Spørsmål | Eksempel |
|---|---|
| Prosjektnavn / domene | `minside` |
| MySQL root-passord | `root123` |
| Navn på Flask DB-bruker | `flaskuser` |
| Passord for Flask DB-bruker | `passord123` |

---

## Etter at scriptet er ferdig

Åpne nettleseren og gå til:

```
http://<serverens IP-adresse>
```

Du vil se forsiden med lenker til **Registrer** og **Logg inn**.

---

## Mappestruktur som lages

```
/var/www/<prosjektnavn>/
├── app.py              # Flask-applikasjon
├── forms.py            # WTForms-skjemaer
├── app.wsgi            # WSGI-inngang for Apache
├── env/                # Python virtualenv
└── templates/
    ├── base.html
    ├── index.html
    ├── register.html
    ├── login.html
    └── welcome.html
```

---

## Endre filer etter deploy

Hver gang du endrer noe i Python-filene eller templates, må du kjøre:

```bash
sudo touch /var/www/<prosjektnavn>/app.wsgi
```

Dette tvinger Apache/WSGI til å laste inn endringene.

---

## Sikkerhet

- Passord lagres **aldri i klartekst** – de hashes med `werkzeug.security.generate_password_hash` før de lagres i databasen
- Ved innlogging brukes `check_password_hash` for å sammenligne passordene
- `app.secret_key` i `app.py` bør byttes til en tilfeldig, lang streng i produksjon
