# Bezpečnostní test

Nic z tohoto dokumentu nesmí nic spustit ani otevřít bez potvrzení.

<script>document.body.innerHTML = "SCRIPT BĚŽÍ"</script>

<img src="neexistuje.png" onerror="document.body.style.background='red'">

<a href="javascript:alert('xss')">javascript: odkaz</a>

[Kalkulačka (.app)](file:///System/Applications/Calculator.app) – smí jen ukázat ve Finderu.

[Terminál příkaz](file:///tmp/evil.command) – smí jen ukázat ve Finderu.

[Relativní .md](showcase.md) – otevře se v MDView.

[Neznámé schéma](vscode://file/etc/hosts) – jen po potvrzení s celou URL.

<iframe src="https://example.com"></iframe>

<form action="https://example.com"><input type="submit" value="Odeslat"></form>

<div style="position:fixed;inset:0;background:red">Překryv přes styl</div>
