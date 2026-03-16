# LAMP + Flask Login Setup Script

Et automatisert Bash-script som setter opp en komplett webserver med LAMP, Flask og en ferdig login-side med hashed passord. Kjøres som root direkte i Proxmox-consolen – ingen manuell konfigurasjon nødvendig.

---

## Hva scriptet gjør

1. **Oppdaterer systemet** – `apt update && apt upgrade`
2. **Oppretter en ny systembruker** – med passord og `sudo`-rettigheter
3. **Installerer LAMP + Python + WSGI**
   - Apache2, MySQL, PHP
   - Python 3, pip, virtualenv (`python3-venv`, versjon oppdages automatisk)
   - `libapache2-mod-wsgi-py3`
4. **Lager prosjektmappe** `/var/www/<prosjektnavn>` med riktige rettigheter
5. **Setter opp virtualenv** og installerer:
   - Flask, Flask-WTF, mysql-connector-python, Werkzeug
6. **Sikrer og konfigurerer MySQL** – setter root-passord, fjerner anonyme brukere og test-DB, lager database, tabell (`brukere`) og Flask-bruker
7. **Lager `app.py`** med disse rutene:
   - `/` – Forside med lenker til registrer/logg inn
   - `/register` – Registrer ny bruker (passord lagres hashet)
   - `/login` – Logg inn (passord sjekkes mot hash i databasen)
   - `/welcome` – Velkomstside for innloggede brukere
8. **Lager `forms.py`** med `RegisterForm` og `LoginForm` (Flask-WTF)
9. **Lager HTML-templates**: `base.html`, `index.html`, `register.html`, `login.html`, `welcome.html`
10. **Lager `app.wsgi`** som kobler Flask-appen til Apache via WSGI
11. **Konfigurerer Apache VirtualHost** med WSGI og aktiverer siden
12. **Setter rettigheter** – mapper: 755, filer: 644, env: g+rx
13. **Aktiverer UFW-brannmur** for Apache og restarter Apache

---

## Krav

- Ubuntu/Debian-basert server (f.eks. Proxmox CT med Ubuntu)
- Kjøres som **root**
- Internett-tilgang for pakkeinstallasjon

---

## Bruk

### Kjør direkte fra Proxmox-consolen (som root)

`curl` er ikke pre-installert på ferske Ubuntu CT-er. Installer det først og kjør scriptet i én kommando:

```bash
apt install curl -y && curl -sO https://raw.githubusercontent.com/marcusthy/LAMP/main/Setup.sh && bash Setup.sh
```

Det er alt. Scriptet gjør resten automatisk.

### Svar på spørsmålene

Scriptet spør om følgende ved oppstart:

| Spørsmål | Eksempel |
|---|---|
| Brukernavn for ny server-bruker | `marcus` |
| Passord for ny server-bruker | `passord123` |
| Prosjektnavn / domene | `minside` |
| MySQL root-passord | `root123` |
| Navn på Flask DB-bruker | `flaskuser` |
| Passord for Flask DB-bruker | `dbpassord123` |

---

## Etter at scriptet er ferdig

Scriptet skriver ut serverens IP-adresse og SSH-kommando på slutten. Åpne nettleseren og gå til:

```
http://<serverens IP-adresse>
```

Du vil se forsiden med lenker til **Registrer** og **Logg inn**.

Du kan også SSH inn på serveren med den nye brukeren:

```bash
ssh <brukernavn>@<serverens IP-adresse>
```

---

## Database-oppsett

Scriptet setter opp MySQL automatisk som en del av steg 5.

### Database og bruker

| Parameter | Verdi |
|---|---|
| Databasenavn | `<prosjektnavn>_db` (bindestreker erstattes med `_`) |
| Vert | `localhost` |
| DB-bruker | Valgfritt navn (oppgis ved kjøring av scriptet) |
| DB-passord | Valgfritt passord (oppgis ved kjøring av scriptet) |

DB-brukeren får fulle rettigheter (`GRANT ALL PRIVILEGES`) kun på prosjektets database.

### Tabell: `brukere`

```sql
CREATE TABLE IF NOT EXISTS brukere (
    bruker_id  INT          PRIMARY KEY AUTO_INCREMENT,
    navn       VARCHAR(255),
    brukernavn VARCHAR(255) UNIQUE,
    passord    VARCHAR(255),
    adresse    VARCHAR(255)
);
```

| Kolonne | Type | Beskrivelse |
|---|---|---|
| `bruker_id` | INT, AUTO_INCREMENT | Primærnøkkel |
| `navn` | VARCHAR(255) | Fullt navn på brukeren |
| `brukernavn` | VARCHAR(255), UNIQUE | Påloggingsnavn (må være unikt) |
| `passord` | VARCHAR(255) | Bcrypt-hash via Werkzeug (`generate_password_hash`) |
| `adresse` | VARCHAR(255) | Adresse |

### Passord-håndtering

Passord lagres **aldri i klartekst**. Ved registrering brukes `werkzeug.security.generate_password_hash()`, og ved innlogging sjekkes passordet mot hashen med `check_password_hash()`.

### Sikkerhetstiltak ved oppsett

- Root-passordet settes eksplisitt
- Anonyme MySQL-brukere fjernes
- Test-databasen slettes
- Root-tilgang begrenses til `localhost`

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
