# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Kontext

`l10n_ch_sepa` ist ein **Odoo 8.0**-Modul (Python 2.7, `__openerp__.py`, `openerp.*`-Imports) aus dem OCA-Repo `l10n-switzerland`, geforkt von Glue Software Engineering AG. Es erzeugt pain.001-Zahlungsdateien (Credit Transfer) aus einem `payment.order`. Glue-eigene Änderungen (Ticket-Präfix `OERPGLUE-…`) betreffen v.a. QR-Rechnungen (Referenztypen `QRR`/`SCOR`).

Python-2-Syntax beibehalten (`except X, e:`, `StringIO`, `dict.items() + …`). Der Code mischt alte API (`cr, uid, ids, context`, `pooler`, `orm.except_orm`) und neue API (`models.TransientModel`, `fields`, `exceptions.Warning`) – im jeweiligen Stil der umgebenden Funktion bleiben.

## Tests

Es gibt nur YAML-Tests (`test/pain001_eu.yml`, `test/pain001_ch.yml`, im Manifest unter `"test"`). Sie laufen beim Installieren/Updaten des Moduls mit aktivierten Tests:

```
openerp-server -d <db> -u l10n_ch_sepa --test-enable --stop-after-init
```

Abhängigkeiten aus anderen OCA-Repos stehen in `../oca_dependencies.txt` (u.a. `bank-payment` für `account_payment`).

## Architektur

Ablauf der Dateierzeugung:

1. **Wizard** `wizard/wiz_pain_001.py` (`wizard.pain001`, gestartet aus dem Payment Order): bestimmt den Ländercode aus der Bank des Payment Mode (Fallback: Land der Firma) und holt via `MsgSEPAFactory` die Nachrichtendefinition `pain.001.<cc>` – existiert keine, wird generisch `pain.001` verwendet. Das Ergebnis wird als `ir.attachment` am `payment.order` gespeichert.
2. **Factory/Registry** `base_sepa/msg_sepa.py`: `MsgSEPAFactory.register_class(key, cls, **args)` – Länderdefinitionen registrieren sich beim Modul-Import. `MsgSEPA._is_xsd_valid()` validiert das erzeugte XML gegen das XSD.
3. **`Pain001`** `base_sepa/pain_001.py`: `_check_data()` prüft Payment Order (Status, Firmen-/Kreditorbank, BIC, IBAN/Kontonummer), dann rendert `compute_export()` das Mako-Template und validiert gegen das XSD.
4. **Schweizer Varianten** `l10n_ch/pain_001_ch.py`: registriert dieselbe Klasse `Pain001` mit anderem XSD/Template – `pain.001.ch` = **pain.001.001.09.ch.03** (SPS 2022+, Default) und `pain.001.ch.02` = alte Version pain.001.001.03.ch.02. Neue Länder/Versionen werden genauso hinzugefügt (`register_class`), keine Subklasse nötig.
5. **Override**: Ist der Systemparameter `l10n_ch_sepa.pain_001_definition` gesetzt (z.B. `pain.001.ch.02`), verwendet der Wizard diese Definition statt der länderbasierten.

### Mako-Templates (hier steckt die meiste Logik)

- **pain.001.001.09.ch.03** (`l10n_ch/template/pain.001.001.09.ch.03.xml.mako`) ist **eigenständig** und erbt nicht vom Basis-Template (Struktur von v09 weicht ab: `ReqdExctnDt/Dt`, `BICFI`, `InitgPty` ohne Adresse, `CtctDtls/Othr/ChanlTp`). `bic()` ist eine Python-Funktion im `<%! %>`-Block – Mako-`<%def>`s schreiben in den Output-Buffer und liefern `''`, taugen also nicht in `% if`-Bedingungen. SCOR wird hier als `Cd`, QRR als `Prtry` ausgegeben. Das XSD stammt aus dem SIX-Paket `ig-credit-transfer-xml-schema-sps-2026-en.zip`, mit **einer** Anpassung: Im `SPSText`-Pattern sind die Zeichen umgestellt (gleiche Bedeutung, kommentiert im XSD), weil libxml2 2.9.4 im Odoo-Container das Original nicht parsen kann (`XMLSchemaParseError`). Bei einem neuen SIX-XSD diese Anpassung wiederholen. Tests deshalb im Container ausführen (`docker exec odoo-cloud python2 …`, Addons unter `/var/lib/odoo/addons/github/`), nicht nur lokal mit neuerer libxml2.

Die folgenden Punkte betreffen die alte Version 03:

- `base_sepa/base_template/pain.001.001.03.xml.mako` ist das Basis-Template mit `<%block>`s (`root`, `InitgPty`, `PmtInf`, `PmtTpInf`, `CdtrAgt`, `RmtInf`) und `<%def>`s (`address`, `acc_id`).
- `l10n_ch/template/pain.001.001.03.ch.02.xml.mako` erbt per `<%inherit>` und überschreibt diese Blöcke. Die aktuelle Zahlungszeile kommt über `sepa_context['line']` (wird in der Schleife des Basis-Templates gesetzt); die Rechnung über `line.move_line_id.invoice`.
- Template-Variablen: `order`, `thetime`, `module_version`, `sepa_context`. Default-Filter sind `unicode, x` (XML-Escaping).
- Im CH-Template steuert `invoice.reference_type` den `RmtInf`-Block (`bvr`, `none`, `QRR`, `SCOR`); `partner_bank_id.state == 'bvr'` steuert `PmtTpInf` (CH01) und das Weglassen von `CdtrAgt`. Die Werte `QRR`/`SCOR` für `reference_type` werden in `../l10n_ch_payment_slip/invoice.py` bzw. `../l10n_ch_qr_bill` definiert.
- Jede Template-Änderung muss weiterhin gegen das jeweilige XSD validieren (ohne Odoo prüfbar: Template mit Mock-Objekten via `mako.lookup.TemplateLookup` rendern, gleiche Optionen wie in `base_sepa/pain_001.py`, und mit `lxml.etree.XMLSchema` validieren) – sonst schlägt die Erzeugung mit „XML is not Valid“ fehl. Fehler beim Rendern werden als Mako-Text-Traceback geworfen.
